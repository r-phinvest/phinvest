#!/bin/bash

IDS=$(psql -qtnA -c "select id from data_sources where id not in (100, 103)")
#IDS="1 101 102 804"

echo "entries"
psql -qtnA -c "
	select id, t as type, case when position('(formerly' in name) = 0 then name else trim(substring(name from E'(^.*)\\\(formerly')) end as name, currency, type as fund_type, classification as asset_type
	from (select 'fund' as t, fund_id as id, fund_web_id, name, institution, currency, type, classification from funds
	      union
	      select 'index' as t, id, web_id as fund_web_id, name, 'Philippine Stock Exchange' as institution, 'PHP' as currency, 'INDEX' as type, 'Equity' as classification from pse_indexes
	      union
	      select 'portfolio' as t, portfolio_id as id, null as fund_web_id, title as name, title as institution, 'PHP' as currency, 'PORTFOLIO' as type, 'Equity' as classification from portfolios where portfolio_id in (101, 102)) foo
" | awk '
BEGIN { printf "var entries = {" }
FNR > 1 { printf ",\n" }
{
split($0, a, "|");
printf("\"%d\":{\"type\":\"%s\",\"name\":\"%s\"}", a[1], a[2], a[3]);
}
END { printf "};" }
' > entries.js

echo "navps"
echo $IDS | tr ' ' '\n' | while read id; do
    echo -n "$id "
    psql -qtnA -c "select * from data_series where id = $id order by trade_date" | awk '
    BEGIN { printf "{\"data\":[" }
    FNR > 1 { printf "," }
    {
	split($0, a, "|");
	split(a[2], t, "-");
	printf "[%d000,%f]", mktime(t[1] " " t[2] " " t[3] " 00 00 00"), a[3];
    }
    END { printf "]}" }' > data/$id.json
done
echo

echo "sma5"
echo $IDS | tr ' ' '\n' | while read id; do
    if [[ $id -lt 100 ]]; then
	ID=id
	TABLE=pse_index_historical_sma5
    elif [[ $id -lt 200 ]]; then
	ID=portfolio_id
	TABLE=portfolio_history_sma5
    else
	ID=fund_id
	TABLE=fund_historical_sma5
    fi
    echo -n "$id "
    psql -qtnA -c "select * from $TABLE where $ID = $id order by trade_date" | awk '
	BEGIN { printf "{\"data\":[" }
	FNR > 1 { printf "," }
	{
	    split($0, a, "|");
	    split(a[2], t, "-");
	    printf "[%d000,%f]", mktime(t[1] " " t[2] " " t[3] " 00 00 00"), a[3];
	}
	END { printf "]}" }' > data/${id}-sma5.json
done

for p in 1 3 5 7 10 15 20; do
    echo "period $p"
    echo $IDS | tr ' ' '\n' | while read id; do
	if [[ $id -lt 100 ]]; then
	    ID=id
	    TABLE=pse_index_historical
	    VALUE=close
	elif [[ $id -lt 200 ]]; then
	    ID=portfolio_id
	    TABLE=portfolio_history
	    VALUE=navps
	else
	    ID=fund_id
	    TABLE=fund_historical
	    VALUE=navps
	fi
	echo -n "$id "
	psql -qtnA -c "
select *
from (select $ID as id, trade_date,
      (select $VALUE
       from $TABLE
       where $ID = h.$ID
       and trade_date >= (h.trade_date + '$p years'::interval)
       order by trade_date
       limit 1) / $VALUE - 1 as r
      from $TABLE h
      where $ID = $id
      and trade_date <= (current_date - '$p years'::interval)) foo
where r is not null
order by trade_date
" | awk '
	BEGIN { printf "{\"data\":[" }
	FNR > 1 { printf "," }
	{
	    split($0, a, "|");
	    split(a[2], t, "-");
	    printf "[%d000,%f]", mktime(t[1] " " t[2] " " t[3] " 00 00 00"), a[3];
	}
	END { printf "]}" }' > data/${id}-${p}.json
    done
    echo
done

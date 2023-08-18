#!/bin/sh

cd /var/www/dharmatech.dev/data/net-liquidity.ps1

script -q -c 'pwsh -Command ./net-liquidity-earnings-remittances.ps1 -display_chart_url -save_iframe' script-out-nl

cat script-out-nl |
    /home/dharmatech/go/bin/terminal-to-html -preview |
    sed 's/pre-wrap/pre/' |
    sed 's/terminal-to-html Preview/Net Liquidity Table/' |
    sed 's/<body>/<body style="width: fit-content;">/' > ../reports/net-liquidity-table.html

mv net-liquidity-chart.html  ../reports
mv spx-fair-value-chart.html ../reports

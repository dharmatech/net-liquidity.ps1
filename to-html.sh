#!/bin/sh

script -q -c 'pwsh -Command ./net-liquidity-earnings-remittances.ps1 -display_chart_url -save_iframe' script-out-nl

# cat script-out-nl | /home/dharmatech/go/bin/terminal-to-html -preview > net-liquidity-table.html

# cat script-out-nl | /home/dharmatech/go/bin/terminal-to-html -preview > net-liquidity-table-preview.html

# cat script-out-nl | /home/dharmatech/go/bin/terminal-to-html          > net-liquidity-table-partial.html

cat script-out-nl |
    /home/dharmatech/go/bin/terminal-to-html -preview |
    sed 's/pre-wrap/pre/' |
    sed 's/terminal-to-html Preview/Net Liquidity Table/' |
    sed 's/<body>/<body style="width: fit-content;">/' > net-liquidity-table.html

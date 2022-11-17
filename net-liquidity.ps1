
function get-recent-tga ()
{
    $date = (Get-Date).AddDays(-4*30).ToString('yyyy-MM-dd')

    $result = Invoke-RestMethod -Method Get -Uri ('https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/dts_table_1?filter=record_date:gte:{0},account_type:eq:Treasury General Account (TGA) Closing Balance&fields=record_date,open_today_bal' -f $date)

    $result
}

function get-recent-reverse-repo ()
{
    $date = (Get-Date).AddDays(-4*30).ToString('yyyy-MM-dd')

    $result = Invoke-RestMethod ('https://markets.newyorkfed.org/api/rp/reverserepo/propositions/search.json?startDate={0}' -f $date)

    $result
}

function get-recent-walcl ()
{
    $result = Invoke-RestMethod 'https://fred.stlouisfed.org/graph/fredgraph.csv?id=WALCL'

    $result | ConvertFrom-Csv
}

function get-sp500 ()
{
    $date = (Get-Date).AddDays(-4*30).ToString('yyyy-MM-dd')

    $result = Invoke-RestMethod ('https://fred.stlouisfed.org/graph/fredgraph.csv?id=SP500&cosd={0}' -f $date)
    
    $result | ConvertFrom-Csv | Where-Object SP500 -NE '.'
}

$tga = get-recent-tga
$rrp = get-recent-reverse-repo
$fed = get-recent-walcl
$sp  = get-sp500

$tga_sorted = $tga.data            | Sort-Object record_date
$rrp_sorted = $rrp.repo.operations | Sort-Object operationDate | Where-Object note -NotMatch 'Small Value Exercise'
$fed_sorted = $fed                 | Sort-Object DATE
$sp_sorted  = $sp                  | Sort-Object DATE

$tga_dates = $tga.data            | ForEach-Object { $_.record_date }
$rrp_dates = $rrp.repo.operations | ForEach-Object { $_.operationDate }
$fed_dates = $fed                 | ForEach-Object { $_.DATE }

$earliest = ($tga_dates | Sort-Object)[0]

$dates = 
    @($tga.data            | ForEach-Object { $_.record_date   }) +
    @($rrp.repo.operations | ForEach-Object { $_.operationDate }) +
    @($fed                 | ForEach-Object { $_.DATE          }) +
    @($sp                  | ForEach-Object { $_.DATE          }) | 
    Sort-Object | 
    Select-Object -Unique | 
    Where-Object { $_ -ge $earliest }

$table = foreach ($date in $dates)
{
    $tga_record = $tga_sorted.Where({ $_.record_date   -le $date }, 'Last')[0]
    $rrp_record = $rrp_sorted.Where({ $_.operationDate -le $date }, 'Last')[0]
    $fed_record = $fed_sorted.Where({ $_.DATE          -le $date }, 'Last')[0]
    $sp_record  = $sp_sorted.Where( { $_.DATE          -le $date }, 'Last')[0]

    $fed = [decimal] $fed_record.WALCL * 1000 * 1000
    $rrp = [decimal] $rrp_record.totalAmtAccepted
    $tga = [decimal] $tga_record.open_today_bal * 1000 * 1000

    $net_liquidity = $fed - $tga - $rrp

    $spx = [math]::Round($sp_record.SP500, 0)

    $spx_fv = [math]::Round($net_liquidity / 1000 / 1000 / 1000 / 1.1 - 1625, 0)

    $spx_low = $spx_fv - 150
    $spx_high = $spx_fv + 350
   
    [pscustomobject]@{
        date = $date
        fed = $fed
        rrp = $rrp
        tga = $tga

        net_liquidity = $net_liquidity

        spx      = $spx
        spx_fv   = $spx_fv
        spx_low  = $spx_low
        spx_high = $spx_high
    }
}

# ----------------------------------------------------------------------

$prev = $table[0]

foreach ($elt in $table | Select-Object -Skip 1)
{
    $fed_change = $elt.fed           - $prev.fed;            $fed_color = if ($fed_change -gt 0) { 'Green' } elseif ($fed_change -lt 0) { 'Red'   } else { 'White' }
    $tga_change = $elt.tga           - $prev.tga;            $tga_color = if ($tga_change -gt 0) { 'Red'   } elseif ($tga_change -lt 0) { 'Green' } else { 'White' }
    $rrp_change = $elt.rrp           - $prev.rrp;            $rrp_color = if ($rrp_change -gt 0) { 'Red'   } elseif ($rrp_change -lt 0) { 'Green' } else { 'White' }
    $nl_change  = $elt.net_liquidity - $prev.net_liquidity;  $nl_color  = if ($nl_change  -gt 0) { 'Green' } elseif ($nl_change  -lt 0) { 'Red'   } else { 'White' }
    
    Write-Host $elt.date -NoNewline; Write-Host ' ' -NoNewline
       
    Write-Host ('{0,20}' -f $elt.fed.ToString('N0'))           -NoNewline; Write-Host ('{0,20}' -f $fed_change.ToString('N0')) -ForegroundColor $fed_color -NoNewline
    Write-Host ('{0,20}' -f $elt.rrp.ToString('N0'))           -NoNewline; Write-Host ('{0,20}' -f $rrp_change.ToString('N0')) -ForegroundColor $rrp_color -NoNewline
    Write-Host ('{0,20}' -f $elt.tga.ToString('N0'))           -NoNewline; Write-Host ('{0,20}' -f $tga_change.ToString('N0')) -ForegroundColor $tga_color -NoNewline
    Write-Host ('{0,20}' -f $elt.net_liquidity.ToString('N0')) -NoNewline; Write-Host ('{0,20}' -f $nl_change.ToString('N0'))  -ForegroundColor $nl_color  -NoNewline
    Write-Host ('{0,10}' -f $elt.spx_fv)
    
    $prev = $elt
}

#           2022-10-25    8,743,922,000,000                   0   2,195,616,000,000     -46,428,000,000     636,785,000,000                   0   5,911,521,000,000      46,428,000,000      3749
Write-Host 'DATE                      WALCL              CHANGE                 RRP              CHANGE                 TGA              CHANGE       NET LIQUIDITY              CHANGE    SPX FV'

# ----------------------------------------------------------------------

$json = @{
    chart = @{
        type = 'bar'
        data = @{
            labels = $table.ForEach({ $_.date })
            datasets = @(
                @{
                    label = 'Net Liquidity (trillions USD)'
                    data = $table.ForEach({ $_.net_liquidity / 1000 / 1000 / 1000 / 1000 })
                }
            )
        }
        options = @{
            scales = @{ }
        }
    }
} | ConvertTo-Json -Depth 100

$result = Invoke-RestMethod -Method Post -Uri 'https://quickchart.io/chart/create' -Body $json -ContentType 'application/json'

# Start-Process $result.url

$id = ([System.Uri] $result.url).Segments[-1]

Start-Process ('https://quickchart.io/chart-maker/view/{0}' -f $id)

# ----------------------------------------------------------------------

$json = @{
    chart = @{
        type = 'line'
        data = @{
            labels = $table.ForEach({ $_.date })
            datasets = @(
                @{ label = 'SPX';        data = $table.ForEach({ $_.spx    }) },
                @{ label = 'Fair Value'; data = $table.ForEach({ $_.spx_fv }) },
                @{ label = 'Low';        data = $table.ForEach({ $_.spx_low }) },
                @{ label = 'High';       data = $table.ForEach({ $_.spx_high }) }
            )
        }
        options = @{
            scales = @{ }
        }
    }
} | ConvertTo-Json -Depth 100

$result = Invoke-RestMethod -Method Post -Uri 'https://quickchart.io/chart/create' -Body $json -ContentType 'application/json'

# Start-Process $result.url

$id = ([System.Uri] $result.url).Segments[-1]

Start-Process ('https://quickchart.io/chart-maker/view/{0}' -f $id)
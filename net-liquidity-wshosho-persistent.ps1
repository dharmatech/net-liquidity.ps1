
Param($days = 365*2, [switch]$csv, [switch]$data)

# function get-recent-tga ()
# {
#     $date = (Get-Date).AddDays(-$days).ToString('yyyy-MM-dd')
    
#     $result = Invoke-RestMethod -Method Get -Uri ('https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/dts_table_1?filter=record_date:gte:{0},account_type:eq:Treasury General Account (TGA) Closing Balance&fields=record_date,open_today_bal&page[number]=1&page[size]=300' -f $date)

#     $result
# }




function get-tga ($date)
{
    $uri = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/dts_table_1?filter=record_date:gte:{0},account_type:eq:Treasury General Account (TGA) Closing Balance&fields=record_date,open_today_bal&page[number]=1&page[size]=900"
    $path     = "tga.json"

    if (Test-Path $path)
    {
        $data = Get-Content $path | ConvertFrom-Json
        $last_date = $data[-1].record_date
        $since = (Get-Date $last_date).AddDays(1).ToString('yyyy-MM-dd')
        Write-Host ("Retrieving records since: {0}" -f $since) -ForegroundColor Yellow
        $result = Invoke-RestMethod -Uri ($uri -f $since) -Method Get
        Write-Host ('Records retrieved: {0}' -f $result.data.Count) -ForegroundColor Yellow
        if ($result.data.Count -gt 0)
        {
            $data + $result.data | ConvertTo-Json > $path
            $data + $result.data
        }
        else
        {
            $data
        }
    }
    else
    {
        Write-Host 'Retrieving TGA data' -ForegroundColor Yellow
        $result = Invoke-RestMethod -Uri ($uri -f $date) -Method Get
        Write-Host ('Retrieved {0} records' -f $result.data.Count)
        $result.data | ConvertTo-Json > $path
        $result.data
    }
}

# $data = get-tga '2022-01-01'





function get-recent-reverse-repo ()
{
    $date = (Get-Date).AddDays(-$days).ToString('yyyy-MM-dd')

    $result = Invoke-RestMethod ('https://markets.newyorkfed.org/api/rp/reverserepo/propositions/search.json?startDate={0}' -f $date)

    $result
}

function get-recent-walcl ()
{
    $result = Invoke-RestMethod 'https://fred.stlouisfed.org/graph/fredgraph.csv?id=WALCL'

    $result | ConvertFrom-Csv
}

function get-recent-wshosho ()
{
    $result = Invoke-RestMethod 'https://fred.stlouisfed.org/graph/fredgraph.csv?id=WSHOSHO'

    $result | ConvertFrom-Csv
}

function get-sp500 ()
{
    $date = (Get-Date).AddDays(-$days).ToString('yyyy-MM-dd')

    $result = Invoke-RestMethod ('https://fred.stlouisfed.org/graph/fredgraph.csv?id=SP500&cosd={0}' -f $date)
    
    $result | ConvertFrom-Csv | Where-Object SP500 -NE '.'
}

function delta ($table, $a, $b)
{
    if ($b -eq $null)
    {
        $b = '{0}_change' -f $a
    }

    $prev = $table[0]

    foreach ($elt in $table | Select-Object -Skip 1)
    {
        $change = $elt.$a - $prev.$a

        $elt | Select-Object *, @{ Label = $b; Expression = { $change } }

        $prev = $elt
    }
}
# ----------------------------------------------------------------------
# $tga = get-recent-tga
$tga = get-tga ((Get-Date).AddDays(-$days))
$rrp = get-recent-reverse-repo
$fed = get-recent-wshosho
$sp  = get-sp500

if ($rrp.GetType().Name -eq 'String')
{
    Write-Host 'Issue contacting markets.newyorkfed.org' -ForegroundColor Yellow
    exit 
}

$tga_sorted = $tga                   | Sort-Object record_date
# $rrp_sorted = $rrp.repo.operations | Sort-Object operationDate | Where-Object note -NotMatch 'Small Value Exercise'
$rrp_sorted = $rrp.repo.operations | Sort-Object operationDate | Where-Object note -NotMatch 'Small Value Exercise' | Where-Object totalAmtAccepted -NE 0
$fed_sorted = $fed                 | Sort-Object DATE
$sp_sorted  = $sp                  | Sort-Object DATE

$tga_dates = $tga            | ForEach-Object { $_.record_date }
$rrp_dates = $rrp.repo.operations | ForEach-Object { $_.operationDate }
$fed_dates = $fed                 | ForEach-Object { $_.DATE }

$earliest = ($tga_dates | Sort-Object)[0]

$dates = 
    @($tga                 | ForEach-Object { $_.record_date   }) +
    @($rrp.repo.operations | ForEach-Object { $_.operationDate }) +
    @($fed                 | ForEach-Object { $_.DATE          }) +
    @($sp                  | ForEach-Object { $_.DATE          }) | 
    Sort-Object | 
    Select-Object -Unique | 
    Where-Object { $_ -ge $earliest }
# ----------------------------------------------------------------------
# table
# ----------------------------------------------------------------------
$table = foreach ($date in $dates)
{
    $tga_record = $tga_sorted.Where({ $_.record_date   -le $date }, 'Last')[0]
    $rrp_record = $rrp_sorted.Where({ $_.operationDate -le $date }, 'Last')[0]
    $fed_record = $fed_sorted.Where({ $_.DATE          -le $date }, 'Last')[0]
    $sp_record  = $sp_sorted.Where( { $_.DATE          -le $date }, 'Last')[0]

    # $fed = [decimal] $fed_record.WALCL * 1000 * 1000
    $fed = [decimal] $fed_record.WSHOSHO * 1000 * 1000
    $rrp = [decimal] $rrp_record.totalAmtAccepted
    $tga = [decimal] $tga_record.open_today_bal * 1000 * 1000

    $net_liquidity = $fed - $tga - $rrp

    $spx = [math]::Round($sp_record.SP500, 0)

    # WALCL fair value
    # $spx_fv = [math]::Round($net_liquidity / 1000 / 1000 / 1000 / 1.1 - 1625, 0)
    # $spx_low = $spx_fv - 150
    # $spx_high = $spx_fv + 350
   
    # WSHOSHO fair value
    $spx_fv = [math]::Round($net_liquidity / 1000 / 1000 / 1000 - 1700, 0)
    $spx_high = $spx_fv + 300
    # $spx_low  = $spx_fv - 300
    # $spx_low  = $spx_fv - 250
    $spx_low  = $spx_fv - 200

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

        spx_div_nl = $spx / $net_liquidity * 1000 * 1000 * 1000
    }
}

$table = delta $table 'fed'
$table = delta $table 'rrp'
$table = delta $table 'tga'
$table = delta $table 'net_liquidity'

if ($data) { $table; exit }
# ----------------------------------------------------------------------
function days-in-month ($date)
{
    [datetime]::DaysInMonth((Get-Date $date -Format 'yyyy'), (Get-Date $date -Format 'MM'))
}

# function within-last-days-of-month ($date, $n)
# {
#     ((days-in-month $date) - (Get-Date $date -Format 'dd')) -lt $n
# }

# function rrp-color ($date, $rrp_change)
# {
#     if ($rrp_change -gt 0)
#     {
#         if ((days-in-month $date) - (Get-Date $date -Format 'dd') -lt 3) { 'Yellow' } else { 'Green' }
#     }
#     elseif ($rrp_change -lt 0) { 'Red' }
#     else { 'White' }
# }

function dates-in-month ($date)
{
    # $n = [datetime]::DaysInMonth((Get-Date $date -Format 'yyyy'), (Get-Date $date -Format 'MM'))

    $n = days-in-month $date

    foreach ($dd in 1..$n)
    {
        Get-Date -Year (Get-Date $date -Format 'yyyy') -Month (Get-Date $date -Format 'MM') -Day $dd -Format 'yyyy-MM-dd'
    }
}

function is-weekday ($date)
{
    'Mon Tue Wed Thu Fri' -match (Get-Date $date -Format 'ddd') 
}

function last-weekdays-in-month ($date, $n)
{
    dates-in-month $date | Where-Object { is-weekday $_ } | Select-Object -Last $n
}

function rrp-color ($date, $rrp_change)
{
    if ($rrp_change -gt 0)
    {
        if ($date -in (last-weekdays-in-month $date 3)) { 'Yellow' } else { 'Green' }
    }
    elseif ($rrp_change -lt 0) { 'Red' }
    else { 'White' }
}

function val-to-color ($val)
{
    if     ($val -gt 0) { 'Green' }
    elseif ($val -lt 0) { 'Red'   }
    else                { 'White' }
}

# ----------------------------------------------------------------------
foreach ($elt in $table | Select-Object -Skip 1)
{    
    Write-Host $elt.date -NoNewline; Write-Host ' ' -NoNewline
    
    Write-Host ('{0,20}' -f $elt.fed.ToString('N0'))                                                                            -NoNewline
    Write-Host ('{0,20}' -f $elt.fed_change.ToString('N0'))           -ForegroundColor (val-to-color $elt.fed_change)           -NoNewline
    Write-Host ('{0,20}' -f $elt.rrp.ToString('N0'))                                                                            -NoNewline
    Write-Host ('{0,20}' -f $elt.rrp_change.ToString('N0'))           -ForegroundColor (rrp-color $elt.date $elt.rrp_change)    -NoNewline
    Write-Host ('{0,20}' -f $elt.tga.ToString('N0'))                                                                            -NoNewline
    Write-Host ('{0,20}' -f $elt.tga_change.ToString('N0'))           -ForegroundColor (val-to-color $elt.tga_change)           -NoNewline
    Write-Host ('{0,20}' -f $elt.net_liquidity.ToString('N0'))                                                                  -NoNewline
    Write-Host ('{0,20}' -f $elt.net_liquidity_change.ToString('N0')) -ForegroundColor (val-to-color $elt.net_liquidity_change) -NoNewline
    Write-Host ('{0,10}' -f $elt.spx_fv)    
}

#           2022-10-25    8,743,922,000,000                   0   2,195,616,000,000     -46,428,000,000     636,785,000,000                   0   5,911,521,000,000      46,428,000,000      3749
# Write-Host 'DATE                      WALCL              CHANGE                 RRP              CHANGE                 TGA              CHANGE       NET LIQUIDITY              CHANGE    SPX FV'
Write-Host 'DATE                    WSHOSHO              CHANGE                 RRP              CHANGE                 TGA              CHANGE       NET LIQUIDITY              CHANGE    SPX FV'
# ----------------------------------------------------------------------
if ($csv)
{
    $table | Export-Csv ('net-liquidity-{0}.csv' -f (Get-Date -Format 'yyyy-MM-dd')) -NoTypeInformation
}
# ----------------------------------------------------------------------

$json = @{
    chart = @{
        type = 'bar'
        data = @{
            labels = $table.ForEach({ $_.date })
            datasets = @(
                @{ label = 'NLSHO'; data = $table.ForEach({ $_.net_liquidity / 1000 / 1000 / 1000 / 1000 });                }
                @{ label = 'SHO';   data = $table.ForEach({ $_.fed           / 1000 / 1000 / 1000 / 1000 }); hidden = $true }
                @{ label = 'RRP';   data = $table.ForEach({ $_.rrp           / 1000 / 1000 / 1000 / 1000 }); hidden = $true }
                @{ label = 'TGA';   data = $table.ForEach({ $_.tga           / 1000 / 1000 / 1000 / 1000 }); hidden = $true }
            )
        }
        options = @{
            title = @{ display = $true; text = 'Net Liquidity Components (trillions USD)' }
            scales = @{ }
        }
    }
} | ConvertTo-Json -Depth 100

$result = Invoke-RestMethod -Method Post -Uri 'https://quickchart.io/chart/create' -Body $json -ContentType 'application/json'

$id = ([System.Uri] $result.url).Segments[-1]

Start-Process ('https://quickchart.io/chart-maker/view/{0}' -f $id)
# ----------------------------------------------------------------------
$chart = @{
    type = 'line'
    data = @{
        labels = $table.ForEach({ $_.date })
        datasets = @(
            @{ label = 'SPX';        data = $table.ForEach({ $_.spx      }); pointRadius = 2; borderColor = '#4E79A7' },
            @{ label = 'Fair Value'; data = $table.ForEach({ $_.spx_fv   }); pointRadius = 2; borderColor = '#F28E2B' },
            @{ label = 'Low';        data = $table.ForEach({ $_.spx_low  }); pointRadius = 2; borderColor = '#62ae67' },
            @{ label = 'High';       data = $table.ForEach({ $_.spx_high }); pointRadius = 2; borderColor = '#f06464' }

          # @{ label = 'SPX / NL';   data = $table.ForEach({ $_.spx_div_nl }); pointRadius = 2; borderColor = '#f06464'; hidden = $true }
        )
    }
    options = @{
        
        title = @{ display = $true; text = 'SPX Fair Value (NLSHO based)' }

        scales = @{ }
    }
}

$json = @{
    chart = $chart
} | ConvertTo-Json -Depth 100

$result = Invoke-RestMethod -Method Post -Uri 'https://quickchart.io/chart/create' -Body $json -ContentType 'application/json'

$id = ([System.Uri] $result.url).Segments[-1]

Start-Process ('https://quickchart.io/chart-maker/view/{0}' -f $id)
# ----------------------------------------------------------------------
exit
# ----------------------------------------------------------------------
# Example invocations
# ----------------------------------------------------------------------
. .\net-liquidity.ps1 -days 90

. .\net-liquidity.ps1 -csv
# ----------------------------------------------------------------------
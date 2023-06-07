
Param($date = '2022-04-01', $days = 365*2, [switch]$csv, [switch]$data, [switch]$skip_chart)
# ----------------------------------------------------------------------
function to-datestamp ([Parameter(Mandatory,ValueFromPipeline)][datetime]$val)
{
    $val.ToString('yyyy-MM-dd')
}
# ----------------------------------------------------------------------
function download-tga ($date)
{
    $uri = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/dts_table_1?filter=record_date:gte:{0},account_type:eq:Treasury General Account (TGA) Closing Balance&fields=record_date,open_today_bal&page[number]=1&page[size]=900"    
    Write-Host ('Downloading TGA data since {0}' -f $date) -ForegroundColor Yellow
    $result = Invoke-RestMethod -Uri ($uri -f $date) -Method Get
    Write-Host ('Received {0} records' -f $result.data.Count) -ForegroundColor Yellow
    $result
}

function get-tga-raw ($date = '2020-04-01')
{
    $path = "tga.json"

    if (Test-Path $path)
    {
        $data = Get-Content $path | ConvertFrom-Json
        $last_date = $data[-1].record_date
        $since = (Get-Date $last_date).AddDays(1).ToString('yyyy-MM-dd')
                
        $result = download-tga $since

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
        $result = download-tga $date
        $result.data | ConvertTo-Json > $path
        $result.data
    }
}

function get-tga ($date = '2020-04-01')
{
    $result = get-tga-raw

    foreach ($row in $result)
    {
        $row.open_today_bal = [decimal] $row.open_today_bal
    }

    $result | Sort-Object record_date
}

# ----------------------------------------------------------------------
function download-rrp ($date)
{
    Write-Host ('Downloading RRP data since: {0}' -f $date) -ForegroundColor Yellow
    $result = Invoke-RestMethod ('https://markets.newyorkfed.org/api/rp/reverserepo/propositions/search.json?startDate={0}' -f $date)
    Write-Host ('Received {0} items' -f $result.repo.operations.Count) -ForegroundColor Yellow
    $result.repo.operations | Sort-Object operationDate
}

function get-rrp-raw ($date = '2020-04-01')
{
    $path = "rrp.json"

    if (Test-Path $path)
    {
        $data = Get-Content $path | ConvertFrom-Json
        $last_date = $data[-1].operationDate
        $since = (Get-Date $last_date).AddDays(1) | to-datestamp
        $result = @(download-rrp $since)
        if ($result.Count -gt 0)
        {
            Write-Host ('Adding {0} items' -f $result.Count) -ForegroundColor Yellow
            $new = $data + $result 
            $new | ConvertTo-Json > $path
            $new
        }
        else
        {
            Write-Host 'No new items found' -ForegroundColor Yellow
            $data
        }
    }
    else
    {
        $result = download-rrp $date
        $result | ConvertTo-Json > $path
        $result
    }
}

function get-rrp ($date = '2020-04-01')
{
    $result = get-rrp-raw $date

    foreach ($row in $result)
    {
        $row.totalAmtAccepted = [decimal] $row.totalAmtAccepted
    }

    $result | Sort-Object operationDate
}
# ----------------------------------------------------------------------

# $series = 'WALCL'
# $date = '2023-03-01'

function download-fred-series ($series, $date)
{
    Write-Host ('Downloading {0} series since: {1}' -f $series, $date) -ForegroundColor Yellow
    $result = Invoke-RestMethod ('https://fred.stlouisfed.org/graph/fredgraph.csv?id={0}&cosd={1}' -f $series, $date)
    $data = @($result | ConvertFrom-Csv)
    Write-Host ('Received {0} items' -f $data.Count) -ForegroundColor Yellow
    $data
}

function get-fred-series-raw ($series, $date)
{
    $path = ("{0}.json" -f $series)

    if (Test-Path $path)
    {
        $data = Get-Content $path | ConvertFrom-Json
        $last_date = $data[-1].DATE
        $result = download-fred-series $series $last_date
        $items = $result | Where-Object DATE -gt $last_date

        if ($items.Count -gt 0)
        {
            Write-Host ('Adding {0} items' -f $items.Count)
            $new = $data + $items
            $new | ConvertTo-Json > $path
            $new
        }
        else
        {
            Write-Host 'No new items found' -ForegroundColor Yellow
            $data
        }
    }
    else
    {
        $result = download-fred-series $series $date
        $result | ConvertTo-Json > $path
        $result
    }
}

function get-fred-series ($series, $date = '2020-04-01')
{
    $result = get-fred-series-raw $series $date

    $result = $result | Where-Object $series -NE '.'

    foreach ($row in $result)
    {
        $row.$series = [decimal] $row.$series
    }

    $result | Sort-Object DATE 
}

# function get-sp500 ()
# {
#     $date = (Get-Date).AddDays(-$days).ToString('yyyy-MM-dd')

#     $result = Invoke-RestMethod ('https://fred.stlouisfed.org/graph/fredgraph.csv?id=SP500&cosd={0}' -f $date)
    
#     $result | ConvertFrom-Csv | Where-Object SP500 -NE '.'
# }

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
$tga_result = get-tga-raw $date
$rrp_result = get-rrp     $date
$fed_result = get-fred-series 'WSHOSHO' $date
$sp_result  = get-fred-series 'SP500'   $date

if ($rrp_result.GetType().Name -eq 'String')
{
    Write-Host 'Issue contacting markets.newyorkfed.org' -ForegroundColor Yellow
    exit 
}

$tga_sorted = $tga_result | Sort-Object record_date
$rrp_sorted = $rrp_result | Where-Object note -NotMatch 'Small Value Exercise' | Where-Object totalAmtAccepted -NE 0
$fed_sorted = $fed_result | Sort-Object DATE
$sp_sorted  = $sp_result  | Sort-Object DATE

$earliest = @(
    $tga_sorted[0].record_date
    $rrp_sorted[0].operationDate
    $fed_sorted[0].DATE
    $sp_sorted[0].DATE
) | Measure-Object -Maximum | % Maximum

# $tga_dates = $tga | ForEach-Object { $_.record_date }
# $rrp_dates = $rrp | ForEach-Object { $_.operationDate }
# $fed_dates = $fed | ForEach-Object { $_.DATE }

# $earliest = ($tga_dates | Sort-Object)[0]

$dates = 
    @($tga_result                 | ForEach-Object { $_.record_date   }) +
    @($rrp_result                 | ForEach-Object { $_.operationDate }) +
    @($fed_result                 | ForEach-Object { $_.DATE          }) +
    @($sp_result                  | ForEach-Object { $_.DATE          }) | 
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
if ($skip_chart)
{
    exit
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
dir *.json
del *.json
del rrp.json
# ----------------------------------------------------------------------
. .\net-liquidity-wshosho-persistent.ps1 -skip_chart

Param($date = '2022-01-01', $days = 365*2, [switch]$csv, [switch]$data, [switch]$skip_chart, [switch]$display_chart_url, [switch]$save_iframe)
# ----------------------------------------------------------------------
function to-datestamp ([Parameter(Mandatory,ValueFromPipeline)][datetime]$val)
{
    $val.ToString('yyyy-MM-dd')
}
# ----------------------------------------------------------------------
function download-tga-old ($date)
{
    # $uri = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/dts_table_1?filter=record_date:gte:{0},account_type:eq:Treasury General Account (TGA)&fields=record_date,close_today_bal&page[number]=1&page[size]=900"    
    $uri = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/operating_cash_balance?filter=record_date:gte:{0},account_type:eq:Treasury General Account (TGA)&fields=record_date,close_today_bal&page[number]=1&page[size]=900"
    Write-Host ('Downloading TGA data since {0}' -f $date) -ForegroundColor Yellow
    $result = Invoke-RestMethod -Uri ($uri -f $date) -Method Get
    Write-Host ('Received {0} records' -f $result.data.Count) -ForegroundColor Yellow
    $result    
}

if ((Test-Path tga-old.json) -eq $false)
{
    $tga_result_old = download-tga-old '2022-01-01'

    $tga_result_old.data | Select-Object record_date, @{ Label = 'open_today_bal'; Expression = { $_.close_today_bal } } | ConvertTo-Json -Depth 100 > 'tga-old.json'
}

function get-tga-old ()
{
    $result = Get-Content tga-old.json | ConvertFrom-Json

    foreach ($row in $result)
    {
        $row.open_today_bal = [decimal] $row.open_today_bal
    }

    $result | Sort-Object record_date
}

# ----------------------------------------------------------------------
function download-tga ($date)
{
    # $uri = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/dts_table_1?filter=record_date:gte:{0},account_type:eq:Treasury General Account (TGA) Closing Balance&fields=record_date,open_today_bal&page[number]=1&page[size]=900"    
    $uri = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/operating_cash_balance?filter=record_date:gte:{0},account_type:eq:Treasury General Account (TGA) Closing Balance&fields=record_date,open_today_bal&page[number]=1&page[size]=900"    
    Write-Host ('Downloading TGA data since {0}' -f $date) -ForegroundColor Yellow
    $result = Invoke-RestMethod -Uri ($uri -f $date) -Method Get
    Write-Host ('Received {0} records' -f $result.data.Count) -ForegroundColor Yellow
    $result
}

function get-tga-raw ()
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
            $data + $result.data | ConvertTo-Json -Depth 100 > $path
            $data + $result.data
        }
        else
        {
            $data
        }
    }
    else
    {
        $result = download-tga '2022-04-18'
        $result.data | ConvertTo-Json -Depth 100 > $path
        $result.data
    }
}

function get-tga ()
{
    $result = get-tga-raw

    foreach ($row in $result)
    {
        $row.open_today_bal = [decimal] $row.open_today_bal
    }

    $result | Sort-Object record_date
}

function get-tga-all ()
{
    $old = get-tga-old

    $new = get-tga

    $old + $new
}

# ----------------------------------------------------------------------
function download-rrp ($date)
{
    Write-Host ('Downloading RRP data since: {0}' -f $date) -ForegroundColor Yellow
    $result = Invoke-RestMethod ('https://markets.newyorkfed.org/api/rp/reverserepo/propositions/search.json?startDate={0}' -f $date)

    if ($result.GetType().Name -eq 'String')
    {
        Write-Host 'Issue contacting markets.newyorkfed.org' -ForegroundColor Red
    }
    else
    {
        Write-Host ('Received {0} items' -f $result.repo.operations.Count) -ForegroundColor Yellow
        $result.repo.operations | Sort-Object operationDate
    }
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
            $new | ConvertTo-Json -Depth 100 > $path
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
        $result | ConvertTo-Json -Depth 100 > $path
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
        $items = @($result | Where-Object DATE -gt $last_date)

        if ($items.Count -gt 0)
        {
            Write-Host ('Adding {0} items' -f $items.Count) -ForegroundColor Yellow
            $new = $data + $items
            $new | ConvertTo-Json -Depth 100 > $path
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
        $result | ConvertTo-Json -Depth 100 > $path
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
# $tga_result = get-tga                   $date
$tga_result = get-tga-all

$rrp_result = get-rrp                   $date | Where-Object note -NotMatch 'Small Value Exercise' | Where-Object totalAmtAccepted -NE 0
$fed_result = get-fred-series 'WALCL' $date

$rem_result = get-fred-series 'RESPPLLOPNWW' $date
# $fed_result = get-fred-series 'WSHOSHO' $date
$sp_result  = get-fred-series 'SP500'   $date

if ($rrp_result.GetType().Name -eq 'String')
{
    Write-Host 'Issue contacting markets.newyorkfed.org' -ForegroundColor Yellow
    exit 
}

$earliest = @(
    $tga_result[0].record_date
    $rrp_result[0].operationDate
    $fed_result[0].DATE
    $rem_result[0].DATE
    $sp_result[0].DATE
) | Measure-Object -Maximum | % Maximum

$dates = 
    @($tga_result                 | ForEach-Object { $_.record_date   }) +
    @($rrp_result                 | ForEach-Object { $_.operationDate }) +
    @($fed_result                 | ForEach-Object { $_.DATE          }) +
    @($rem_result                 | ForEach-Object { $_.DATE          }) +
    @($sp_result                  | ForEach-Object { $_.DATE          }) | 
    Sort-Object | 
    Select-Object -Unique | 
    Where-Object { $_ -ge $earliest }
# ----------------------------------------------------------------------
# table
# ----------------------------------------------------------------------
$table = foreach ($date in $dates)
{
    $tga_record = $tga_result.Where({ $_.record_date   -le $date }, 'Last')[0]
    $rrp_record = $rrp_result.Where({ $_.operationDate -le $date }, 'Last')[0]
    $fed_record = $fed_result.Where({ $_.DATE          -le $date }, 'Last')[0]
    $rem_record = $rem_result.Where({ $_.DATE          -le $date }, 'Last')[0]
    $sp_record  = $sp_result.Where( { $_.DATE          -le $date }, 'Last')[0]

    $fed = [decimal] $fed_record.WALCL * 1000 * 1000
    $rem = [decimal] $rem_record.RESPPLLOPNWW * 1000 * 1000
    # $fed = [decimal] $fed_record.WSHOSHO * 1000 * 1000
    $rrp = [decimal] $rrp_record.totalAmtAccepted
    $tga = [decimal] $tga_record.open_today_bal * 1000 * 1000

    $net_liquidity = $fed - $tga - $rrp - $rem

    $spx = [math]::Round($sp_record.SP500, 0)

    # WALCL fair value
    $spx_fv   = [math]::Round($net_liquidity / 1000 / 1000 / 1000 / 1.1 - 1625, 0)
    $spx_low  = $spx_fv - 150
    $spx_high = $spx_fv + 350
    $spx_high_1 = $spx_fv + 350 + 361
   
    # WSHOSHO fair value
    # $spx_fv = [math]::Round($net_liquidity / 1000 / 1000 / 1000 - 1700, 0)
    # $spx_high = $spx_fv + 300
    # $spx_low  = $spx_fv - 200

    [pscustomobject]@{
        date = $date
        fed = $fed
        rrp = $rrp
        tga = $tga
        rem = $rem

        net_liquidity = $net_liquidity

        spx      = $spx
        spx_fv   = $spx_fv
        spx_low  = $spx_low
        spx_high = $spx_high
        spx_high_1 = $spx_high_1

        spx_div_nl = $spx / $net_liquidity * 1000 * 1000 * 1000
    }
}

$table = delta $table 'fed'
$table = delta $table 'rrp'
$table = delta $table 'tga'
$table = delta $table 'rem'
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
#            2023-06-23    8,362,060,000,000                   0   1,969,380,000,000     -25,331,000,000     366,505,000,000                   0     -71,875,000,000                   0   6,098,050,000,000      25,331,000,000      3919
  $header = 'DATE                      WALCL              CHANGE                 RRP              CHANGE                 TGA              CHANGE                 REM              CHANGE       NET LIQUIDITY              CHANGE    SPX FV'
# $header = 'DATE                    WSHOSHO              CHANGE                 RRP              CHANGE                 TGA              CHANGE       NET LIQUIDITY              CHANGE    SPX FV'

Write-Host $header

foreach ($elt in $table | Select-Object -Skip 1)
{    
    Write-Host $elt.date -NoNewline; Write-Host ' ' -NoNewline
    
    Write-Host ('{0,20}' -f $elt.fed.ToString('N0'))                                                                            -NoNewline
    Write-Host ('{0,20}' -f $elt.fed_change.ToString('N0'))           -ForegroundColor (val-to-color $elt.fed_change)           -NoNewline
    Write-Host ('{0,20}' -f $elt.rrp.ToString('N0'))                                                                            -NoNewline
    Write-Host ('{0,20}' -f $elt.rrp_change.ToString('N0'))           -ForegroundColor (rrp-color $elt.date $elt.rrp_change)    -NoNewline
    Write-Host ('{0,20}' -f $elt.tga.ToString('N0'))                                                                            -NoNewline
    Write-Host ('{0,20}' -f $elt.tga_change.ToString('N0'))           -ForegroundColor (val-to-color $elt.tga_change)           -NoNewline
    Write-Host ('{0,20}' -f $elt.rem.ToString('N0'))                                                                            -NoNewline
    Write-Host ('{0,20}' -f $elt.rem_change.ToString('N0'))           -ForegroundColor (val-to-color $elt.rem_change)           -NoNewline    
    Write-Host ('{0,20}' -f $elt.net_liquidity.ToString('N0'))                                                                  -NoNewline
    Write-Host ('{0,20}' -f $elt.net_liquidity_change.ToString('N0')) -ForegroundColor (val-to-color $elt.net_liquidity_change) -NoNewline
    Write-Host ('{0,10}' -f $elt.spx_fv)    
}

Write-Host $header

# ----------------------------------------------------------------------
# TGA refill note
# ----------------------------------------------------------------------
$a = $table | ? date -EQ '2023-06-01'
# $a = $table | ? date -EQ '2023-06-02'
# $a = $table | ? date -EQ '2023-06-05'
$b = $table[-1]

$tga_change = $b.tga - $a.tga
$rrp_change = $b.rrp - $a.rrp

$rest = $tga_change + $rrp_change

# Write-Host 'Since 2023-06-01:' -ForegroundColor Yellow
# Write-Host
# Write-Host ('TGA change                  {0,17}'    -f $tga_change.ToString('N0'))         -ForegroundColor Yellow
# Write-Host ('RRP change                  {0,17}'    -f $rrp_change.ToString('N0'))         -ForegroundColor Yellow
# Write-Host ('TGA refill covered by RRP   {0,4:N0}%' -f (-$rrp_change / $tga_change * 100)) -ForegroundColor Yellow
# Write-Host ('Not covered by RRP          {0,17}'    -f $rest.ToString('N0'))               -ForegroundColor Yellow

# Write-Host

function days-remaining-until ([datetime]$date)
{
    ($date - (Get-Date)).Days
}

$sep30_target = 650000000000
$oct31_target = 750000000000
$dec31_target = 750000000000

# Write-Host ("TGA change needed for Sept 30th target: {0:N0}    days remaining: {1}   amount per day: {2:N0}" -f ($sep30_target - $b.tga), (days-remaining-until '2023-09-30'), (($sep30_target - $b.tga) / (days-remaining-until '2023-09-30')))  -ForegroundColor Yellow
# Write-Host ('TGA change needed for Oct  31th target: {0:N0}    days remaining: {1}   amount per day: {2:N0}' -f ($oct31_target - $b.tga), (days-remaining-until '2023-10-31'), (($oct31_target - $b.tga) / (days-remaining-until '2023-10-31')))  -ForegroundColor Yellow

# Write-Host ("TGA change needed for Sept 30th target: {0:N0} B    days remaining: {1}   amount per day: {2:N1} B" -f (($sep30_target - $b.tga) / 1000 / 1000 / 1000), (days-remaining-until '2023-09-30'), (($sep30_target - $b.tga) / 1000 / 1000 / 1000 / (days-remaining-until '2023-09-30')))  -ForegroundColor Yellow
# Write-Host ('TGA change needed for Oct  31th target: {0:N0} B    days remaining: {1}   amount per day: {2:N1} B' -f (($oct31_target - $b.tga) / 1000 / 1000 / 1000), (days-remaining-until '2023-10-31'), (($oct31_target - $b.tga) / 1000 / 1000 / 1000 / (days-remaining-until '2023-10-31')))  -ForegroundColor Yellow

function to-billions ($val)
{
    $val / 1000 / 1000 / 1000
}

# Write-Host ("TGA Sept 30th target: {3:N0} B   change needed: {0:N0} B    days remaining: {1}   amount per day: {2:N1} B   RRP level for 100% coverage: $($PSStyle.Foreground.Green){4:N0} B$($PSStyle.Reset)" -f (($sep30_target - $b.tga) / 1000 / 1000 / 1000), (days-remaining-until '2023-09-30'), (($sep30_target - $b.tga) / 1000 / 1000 / 1000 / (days-remaining-until '2023-09-30')), ($sep30_target / 1000 / 1000 / 1000), (to-billions ($b.rrp - ($sep30_target - $b.tga))))  -ForegroundColor Yellow
# Write-Host ("TGA Oct  31st target: {3:N0} B   change needed: {0:N0} B    days remaining: {1}   amount per day: {2:N1} B   RRP level for 100% coverage: $($PSStyle.Foreground.Green){4:N0} B$($PSStyle.Reset)" -f (($oct31_target - $b.tga) / 1000 / 1000 / 1000), (days-remaining-until '2023-10-31'), (($oct31_target - $b.tga) / 1000 / 1000 / 1000 / (days-remaining-until '2023-10-31')), ($oct31_target / 1000 / 1000 / 1000), (to-billions ($b.rrp - ($oct31_target - $b.tga))))  -ForegroundColor Yellow

$rrp_sep_30_coverage = $b.rrp - ($sep30_target - $b.tga)
$rrp_oct_31_coverage = $b.rrp - ($oct31_target - $b.tga)
$rrp_dec_31_coverage = $b.rrp - ($dec31_target - $b.tga)  # RRP level for 100% TGA coverage

# Write-Host ("TGA Sept 30th target: {3:N0} B   change needed: {0,3:N0} B    days remaining: {1,3}   amount per day: {2,5:N1} B   RRP level for 100% coverage: {4:N0} B" -f (($sep30_target - $b.tga) / 1000 / 1000 / 1000), (days-remaining-until '2023-09-30'), (($sep30_target - $b.tga) / 1000 / 1000 / 1000 / (days-remaining-until '2023-09-30')), ($sep30_target / 1000 / 1000 / 1000), (to-billions ($b.rrp - ($sep30_target - $b.tga))))  -ForegroundColor Yellow
# # Write-Host ("TGA Oct  31st target: {3:N0} B   change needed: {0:N0} B    days remaining: {1}   amount per day: {2:N1} B   RRP level for 100% coverage: {4:N0} B" -f (($oct31_target - $b.tga) / 1000 / 1000 / 1000), (days-remaining-until '2023-10-31'), (($oct31_target - $b.tga) / 1000 / 1000 / 1000 / (days-remaining-until '2023-10-31')), ($oct31_target / 1000 / 1000 / 1000), (to-billions ($b.rrp - ($oct31_target - $b.tga))))  -ForegroundColor Yellow
# Write-Host ("TGA Dec  31st target: {3:N0} B   change needed: {0,3:N0} B    days remaining: {1,3}   amount per day: {2,5:N1} B   RRP level for 100% coverage: {4:N0} B" -f `
#     (($dec31_target - $b.tga) / 1000 / 1000 / 1000), 
#     (days-remaining-until '2023-12-31'), 
#     (($dec31_target - $b.tga) / 1000 / 1000 / 1000 / (days-remaining-until '2023-12-31')), 
#     ($dec31_target / 1000 / 1000 / 1000), 
#     (to-billions $rrp_dec_31_coverage))  -ForegroundColor Yellow

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

$html_template = @"
<!DOCTYPE html>
<html>
    <head>
        <title>{0}</title>
    </head>
    <body>
        <div style="padding-bottom: 56.25%; position: relative; display:block; width: 100%;">
            <iframe width="100%" height="100%" src="https://quickchart.io/chart-maker/view/{1}" frameborder="0" style="position: absolute; top:0; left: 0"></iframe>
        </div>
    </body>
</html>
"@

# $html_template -f 'Net Liquidity', $id

# ----------------------------------------------------------------------
$items = $table | Select-Object -Last $days

$json = @{
    chart = @{
        type = 'bar'
        data = @{
            labels = $items.ForEach({ $_.date })
            datasets = @(
                # @{ label = 'RRP Sep 30th TGA coverage';     data = $items.ForEach({ $rrp_sep_30_coverage / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0; borderColor = '#EDC948' }
                # # @{ label = 'RRP Oct 31st TGA coverage';     data = $items.ForEach({ $rrp_oct_31_coverage / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0; borderColor = '#B07AA1' }
                # @{ label = 'RRP Dec 31st TGA coverage';     data = $items.ForEach({ $rrp_dec_31_coverage / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0; borderColor = '#B07AA1' }

                # @{ label = 'RRP Sep 30th TGA coverage';     data = $items.ForEach({ $rrp_sep_30_coverage / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0 }
                # @{ label = 'RRP Oct 31st TGA coverage';     data = $items.ForEach({ $rrp_oct_31_coverage / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0 }                

                @{ label = 'NL';      data = $items.ForEach({ $_.net_liquidity / 1000 / 1000 / 1000 / 1000 });                }
                @{ label = 'WALCL';   data = $items.ForEach({ $_.fed           / 1000 / 1000 / 1000 / 1000 }); hidden = $true }
              # @{ label = 'WSHOSHO'; data = $items.ForEach({ $_.fed           / 1000 / 1000 / 1000 / 1000 }); hidden = $true }
                @{ label = 'RRP';     data = $items.ForEach({ $_.rrp           / 1000 / 1000 / 1000 / 1000 }); hidden = $true }

                

                @{ label = 'TGA';     data = $items.ForEach({ $_.tga           / 1000 / 1000 / 1000 / 1000 }); hidden = $true }
                @{ label = 'REM';     data = $items.ForEach({ $_.rem           / 1000 / 1000 / 1000 / 1000 }); hidden = $true }

                @{ label = 'TGA Sept 30th target';     data = $items.ForEach({ $sep30_target / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0; hidden = $true }
                @{ label = 'TGA Dec  31st target';     data = $items.ForEach({ $dec31_target / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0; hidden = $true }

                @{ label = 'RRP Sep 30th TGA coverage';     data = $items.ForEach({ $rrp_sep_30_coverage / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0; hidden = $true }
                @{ label = 'RRP Dec 31st TGA coverage';     data = $items.ForEach({ $rrp_dec_31_coverage / 1000 / 1000 / 1000 / 1000 }); type = 'line'; fill = $false; pointRadius = 0; hidden = $true }                
                
                
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

if ($save_iframe)
{
    $html_template -f 'Net Liquidity', $id > net-liquidity-chart.html
}

if ($display_chart_url)
{
    Write-Host

    Write-Host ('Net liquidity: https://quickchart.io/chart-maker/view/{0}' -f $id) -ForegroundColor Yellow
}
else
{
    Start-Process ('https://quickchart.io/chart-maker/view/{0}' -f $id)
}
# ----------------------------------------------------------------------
$chart = @{
    type = 'line'
    data = @{
        labels = $items.ForEach({ $_.date })
        datasets = @(
            @{ label = 'SPX';        data = $items.ForEach({ $_.spx      });   pointRadius = 2; borderColor = '#4E79A7' },
            @{ label = 'Fair Value'; data = $items.ForEach({ $_.spx_fv   });   pointRadius = 2; borderColor = '#F28E2B' },
            @{ label = 'Low';        data = $items.ForEach({ $_.spx_low  });   pointRadius = 2; borderColor = '#62ae67' },
            @{ label = 'High';       data = $items.ForEach({ $_.spx_high });   pointRadius = 2; borderColor = '#f06464' },
            @{ label = 'High + 1';   data = $items.ForEach({ $_.spx_high_1 }); pointRadius = 2; borderColor = '#8b0000' }

          # @{ label = 'SPX / NL';   data = $items.ForEach({ $_.spx_div_nl }); pointRadius = 2; borderColor = '#f06464'; hidden = $true }
        )
    }
    options = @{
        
        title = @{ display = $true; text = 'SPX Fair Value (WALCL based)' }
      # title = @{ display = $true; text = 'SPX Fair Value (WSHOSHO based)' }

        scales = @{ }
    }
}

$json = @{
    chart = $chart
} | ConvertTo-Json -Depth 100

$result = Invoke-RestMethod -Method Post -Uri 'https://quickchart.io/chart/create' -Body $json -ContentType 'application/json'

$id = ([System.Uri] $result.url).Segments[-1]

if ($save_iframe)
{
    $html_template -f 'SPX Fair Value', $id > spx-fair-value-chart.html
}

if ($display_chart_url)
{
    Write-Host ('SPX Fair Value: https://quickchart.io/chart-maker/view/{0}' -f $id) -ForegroundColor Yellow
}
else
{
    Start-Process ('https://quickchart.io/chart-maker/view/{0}' -f $id)
}
# ----------------------------------------------------------------------
exit
# ----------------------------------------------------------------------
# Example invocations
# ----------------------------------------------------------------------

. .\net-liquidity-earnings-remittances.ps1

. .\net-liquidity.ps1 -days 90

. .\net-liquidity.ps1 -csv
# ----------------------------------------------------------------------
dir *.json
del *.json
del rrp.json
# ----------------------------------------------------------------------
. .\net-liquidity-wshosho-persistent.ps1 -skip_chart
# ----------------------------------------------------------------------

. .\net-liquidity-earnings-remittances.ps1 -days 150

. .\net-liquidity-earnings-remittances.ps1 -days 365

. .\net-liquidity-earnings-remittances.ps1 -display_chart_url

. .\net-liquidity-earnings-remittances.ps1 -display_chart_url -save_iframe



$template = Get-Content .\net-liquidity-table-template.html

$template -replace '---BODY---', 123
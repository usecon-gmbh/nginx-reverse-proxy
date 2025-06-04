Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Windows.Forms

$chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
$chart.Width = 1000
$chart.Height = 600

$chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
$chart.ChartAreas.Add($chartArea)

$series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
$series.ChartType = 'Line'
$series.XValueType = 'DateTime'
$series.Name = "Latency"

Import-Csv $LogFile | ForEach-Object {
    if ($_.Status -eq "OK") {
        $timestamp = [datetime]::Parse($_.Timestamp)
        $latency = [double]$_.LatencyMs
        $series.Points.AddXY($timestamp, $latency)
    }
}

$chart.Series.Add($series)

$form = New-Object Windows.Forms.Form
$form.Text = "Latency Over Time"
$form.Width = 1020
$form.Height = 640
$form.Controls.Add($chart)
$chart.Dock = "Fill"
$form.ShowDialog()
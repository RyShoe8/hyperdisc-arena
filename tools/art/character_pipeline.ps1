param(
 [ValidateSet('List','NewJob','Submit','Validate','Accept')][string]$Action='List',
 [ValidateSet('mick','tiffany','pete','steve','vanessa','keno')][string]$Character,
 [ValidatePattern('^[a-z0-9-]+$')][string]$Animation='run-directions-v1',
 [int]$Frames=16,
 [int]$Columns=4,
 [int]$Rows=4,
 [string]$Source,
 [string]$ReviewNotes
)
$ErrorActionPreference='Stop'
$catalog=Get-Content (Join-Path $PSScriptRoot 'characters/catalog.json') -Raw | ConvertFrom-Json
if($Action -eq 'List') { $catalog.characters | Select-Object id,version,base; exit }
if(-not $Character){throw 'Specify -Character.'}
$entry=$catalog.characters | Where-Object id -eq $Character
$baseDir=Join-Path $PSScriptRoot ('characters/'+$Character+'/base-v1')
foreach($name in @('base.png','reference.png')) {
 $actual=(Get-FileHash -LiteralPath (Join-Path $baseDir $name) -Algorithm SHA256).Hash.ToLower()
 if($actual -ne $entry.hashes.$name){throw "Canonical $Character $name has changed. Create and review a new base version instead of overwriting it."}
}
$jobDir=Join-Path $PSScriptRoot ('characters/'+$Character+'/jobs/'+$Animation)
$jobPath=Join-Path $jobDir 'job.json'
function Save-Job($job){$job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jobPath -Encoding utf8}
if($Action -eq 'NewJob') {
 if(Test-Path -LiteralPath $jobPath){throw 'Job already exists; choose a new version name.'}
 if($Frames -lt 1 -or $Frames -gt 64){throw 'Frames must be 1..64.'}
 if($Columns -lt 1 -or $Rows -lt 1 -or $Columns*$Rows -ne $Frames){throw 'Columns times Rows must equal Frames.'}
 New-Item -ItemType Directory -Force -Path $jobDir | Out-Null
 $job=[ordered]@{character=$Character;animation=$Animation;base_version=$entry.version;base_sha256=$entry.hashes.'base.png';reference_sha256=$entry.hashes.'reference.png';expected_frames=$Frames;columns=$Columns;rows=$Rows;status='draft';candidate='candidate.png';candidate_sha256='';review_notes='';accepted_sha256=''}
 Save-Job $job
 $prompt=@"
IDENTITY-PRESERVING ANIMATION EDIT. Use BOTH supplied canonical images:
$baseDir\base.png
$baseDir\reference.png

Character: $Character. Animation: $Animation. Required distinct frames: $Frames, grid $Columns columns by $Rows rows.
Keep the EXACT approved character: face, age, hair silhouette, proportions,
costume cut, accessories, shoes, palette, line weight and pixel clusters.
Identity locks: $($entry.identity_locks -join '; ').
Change only pose and facing needed for the movement. No redesign or reinterpretation.
Transparent background, isolated complete figures, consistent scale and foot anchor.
First make a front/back turnaround for visual comparison. Only after it matches,
animate those same poses. Preserve the canonical references in every generation.
Specify and verify the grid before extracting. Do not accept extra/missing limbs,
lost accessories, altered faces, changed clothes, or inconsistent body mass.
"@
 Set-Content -LiteralPath (Join-Path $jobDir 'prompt.txt') -Value $prompt
 Write-Output "Created $jobPath"
 exit
}
if(-not (Test-Path -LiteralPath $jobPath)){throw 'Create the job with NewJob first.'}
$job=Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
if($job.base_sha256 -ne $entry.hashes.'base.png' -or $job.reference_sha256 -ne $entry.hashes.'reference.png'){throw 'Job references a different base version.'}
$candidate=Join-Path $jobDir $job.candidate
if($Action -eq 'Submit') {
 if(-not $Source -or -not (Test-Path -LiteralPath $Source)){throw 'Specify an existing PNG with -Source.'}
 if(Test-Path -LiteralPath $candidate){throw 'Candidate already exists. Use a new job version; keep previous attempts reviewable.'}
 Copy-Item -LiteralPath $Source -Destination $candidate
 $job.candidate_sha256=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLower()
 $job.status='needs-review'
 $job.accepted_sha256=''
 Save-Job $job
}
if(-not (Test-Path -LiteralPath $candidate)){throw 'No candidate submitted yet.'}
$hash=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLower()
if($hash -ne $job.candidate_sha256){throw 'Candidate changed after submission. Use a new job version.'}
Add-Type -AssemblyName System.Drawing
$bitmap=[System.Drawing.Bitmap]::new($candidate)
try {
 if($bitmap.Width -lt 128 -or $bitmap.Height -lt 128){throw 'Candidate is too small.'}
 if($bitmap.GetPixel(0,0).A -ne 0){throw 'Candidate must have a transparent background.'}
} finally {$bitmap.Dispose()}
if($Action -eq 'Accept') {
 if([string]::IsNullOrWhiteSpace($ReviewNotes)){throw 'Document the visual comparison of identity, proportions, outfit, accessories, pixel style and all frames in -ReviewNotes.'}
 $job.status='accepted'
 $job.accepted_sha256=$hash
 $job.review_notes=$ReviewNotes
 Save-Job $job
}
Write-Output "$Character / $Animation : $($job.status). Base and candidate hashes verified. Visual identity requires direct comparison, not a hash test."

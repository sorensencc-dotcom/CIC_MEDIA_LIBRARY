# CAST IRON CHARLIE — BULK INGESTION GUIDE
## Complete 777+ Images + 92 Documents → DAM in 3 Steps

**Status:** Ready to execute  
**Scope:** 777 images + 92 documents from Google Drive → C:\CIC_MEDIA_LIBRARY\CIC\  
**Time estimate:** 6–8 hours (breakable into daily sessions)  
**Date:** 2026-06-06  

---

## EXECUTIVE SUMMARY

You have:
- **777 images** on Google Drive (Helene yacht, Kroll Willow Run, later life, Willys, etc.)
- **92 documents** (Treatment versions, research logs, Word docs, PDFs)
- **All existing research** (9 topic logs, 13 Treatment versions, correspondence)

**This guide ingests everything into the DAM in one consolidated pass:**

```
STEP 1: Bulk copy from Drive → local staging (organized by batch)
    ↓
STEP 2: Run ingestion pipeline (ingest → classify → organize)
    ↓
STEP 3: Integrate Treatment + research logs + validate
    ↓
Result: 870 items fully indexed in master_media_inventory.csv
```

---

## PREREQUISITE: VERIFY SCRIPTS EXIST

```powershell
ls C:\CIC_MEDIA_LIBRARY\CIC\scripts\

# Should show:
# ingest-cic-archival.ps1
# classify-cic-media.ps1
# organize-cic-media-library.ps1
# maintain-research-log.ps1
# curate-cic-marketing-assets.ps1
# cic-follow-ops.ps1
# bulk-copy-from-drive.ps1 [NEW]
# bulk-ingest-batches.ps1 [NEW]
```

---

## STEP 1: BULK COPY FROM GOOGLE DRIVE

### **What it does:**
- Copies all files from `G:\My Drive\Cast Iron Charlie — Documentary Project\` to local staging
- Organizes by batch (Helene, Kroll, Later Life, Willys, Documents, etc.)
- Generates manifest + topic mapping

### **Execution:**

#### **Option A: DRY RUN (preview what will be copied)**
```powershell
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-copy-from-drive.ps1' -DryRun $true
```
**Output:** Shows what would be copied, creates no files. Review `logs/bulk_copy_*.log`

#### **Option B: ACTUAL COPY (execute)**
```powershell
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-copy-from-drive.ps1'
```

**Output:**
```
C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\
├─ Batch_Helene_Yacht/
│  └─ [~50 images of M/Y Helene]
├─ Batch_Kroll_Willow_Run/
│  └─ [~40+ Kroll photographs]
├─ Batch_Later_Life/
│  └─ [~30 Sorensen later life photos]
├─ Batch_Willys/
│  └─ [~25 Willys-Overland photos]
├─ Batch_Documents/
│  └─ [~92 Word/PDF/TXT files]
├─ drive_copy_manifest.json [inventory of all copied files]
└─ logs/bulk_copy_*.log
```

**Files created:**
- `media/_Inbox/drive_copy_manifest.json` — complete file inventory
- `metadata/folder_to_topic_mapping.json` — Drive → DAM mapping rules

**Time:** ~30 minutes (depends on internet speed)

---

### **Troubleshooting Step 1:**

| Issue | Solution |
|-------|----------|
| "Drive path not found" | Check that `G:\My Drive\` is mounted (Google Drive desktop) |
| "Permission denied" | Ensure you have read access to Drive folder |
| "No space on disk" | Drive has 777 images + 92 docs = ~10-15 GB. Verify free space on C: |
| DryRun shows 0 files | Some folder names might be off. Check exact paths in Drive |

---

## STEP 2: RUN BULK INGESTION PIPELINE

### **What it does:**
For **each batch** (Helene, Kroll, etc.), runs:
1. **Ingest:** HEIC → JPEG, extract metadata, generate SHA-256 hashes, detect duplicates
2. **Classify:** Type detection, topic routing, entity extraction, Treatment cross-refs
3. **Organize:** Assign media IDs (CIC-WR-1944-001, etc.), create By_Topic/By_Type/By_Source links, update inventory CSV

### **Execution:**

#### **Option A: PROCESS ALL BATCHES AT ONCE**
```powershell
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1'
```
**Time:** 3–4 hours (runs continuously)  
**Best if:** You have the time and want it done in one go

#### **Option B: PROCESS SPECIFIC BATCHES (recommended for first pass)**
```powershell
# Just Helene yacht (test batch)
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Helene*"

# Then Kroll
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Kroll*"

# Then others
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Later*"
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Willys*"
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Documents*"
```
**Time:** 30–45 min per batch  
**Best if:** You want to process daily or validate as you go

#### **Option C: VALIDATE WITHOUT RE-PROCESSING**
```powershell
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -ValidateOnly $true
```
**Time:** 5 minutes  
**Best for:** Checking existing data without re-running pipeline

### **What to expect during execution:**

```
========== BULK INGESTION WORKFLOW START ==========
Batch pattern: Batch_Helene*
Found 1 batches to process

========== PROCESSING: Batch_Helene_Yacht ==========
  Files in batch: 52

  PHASE 1: INGEST (HEIC → JPEG)
  ✓ Ingest complete: 52 files

  PHASE 2: CLASSIFY
  ✓ Classification complete: 52 files

  PHASE 3: ORGANIZE (Media IDs + DAM Structure)
  ✓ Organization complete: 52 files
  ✓ Media IDs assigned: 52 total in inventory

✓ BATCH COMPLETE: Batch_Helene_Yacht

========== BULK INGESTION WORKFLOW COMPLETE ==========
Batches processed: 1/1
Total files ingested: 52
Total media IDs in inventory: 52
✓ BULK INGESTION WORKFLOW SUCCESS
```

**Output files:**
- `metadata/master_media_inventory.csv` — updated with new media IDs
- `metadata/search_index.json` — updated
- `metadata/treatment_crossref_index.json` — updated
- `logs/bulk_ingest_*.log` — detailed logs
- `logs/bulk_ingest_report_*.json` — summary report

---

### **Troubleshooting Step 2:**

| Issue | Solution |
|-------|----------|
| "Convert.exe not found" | ImageMagick not installed. Download: https://imagemagick.org/ |
| Batch hangs on HEIC conversion | Large files (100+ MB) may timeout. Check task manager |
| Media IDs not assigned | Run organize script separately: `organize-cic-media-library.ps1` |
| CSV has 0 rows | Check that JSON sidecars were created during ingest |

---

## STEP 3: INTEGRATE TREATMENT + RESEARCH LOGS

### **What it does:**
- Consolidates Treatment versions (v1–v13) → single `Treatment_v13_master.md`
- Integrates research logs from Drive into `research_logs/` folder
- Links all media IDs to research entries
- Validates entire DAM structure

### **Execution:**

#### **3a: Copy Treatment v13**
```powershell
Copy-Item 'G:\My Drive\Cast Iron Charlie — Documentary Project\Documents\Treatment\CastIronCharlie_Treatment_v13_20260523.txt' `
  -Destination 'C:\CIC_MEDIA_LIBRARY\CIC\versions\Treatment_v13_master.md'
```

#### **3b: Copy + Format Research Logs**
```powershell
# Copy each topic log from Drive
Copy-Item 'G:\My Drive\Cast Iron Charlie — Documentary Project\Documents\Research Logs\*_log.*' `
  -Destination 'C:\CIC_MEDIA_LIBRARY\CIC\research_logs\' -Recurse

# Then auto-generate structured indexes
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\maintain-research-log.ps1' -Topic all
```

#### **3c: Generate Treatment Cross-Refs**
```powershell
# Update treatment_crossref_index.json with linked media
$inventory = Import-Csv 'C:\CIC_MEDIA_LIBRARY\CIC\metadata\master_media_inventory.csv'

$crossrefs = @{
  treatment_version = "v13"
  sections = @(
    @{
      section_name = "The Engineering Mind"
      linked_topics = @(
        "1-Willow_Run_Bomber_Plant/Riveting_Production_Women_Workforce",
        "1-Willow_Run_Bomber_Plant/KD_Knockdown_Logistics"
      )
      linked_media = @($inventory | Where-Object { $_.treatment_sections -like "*Engineering*" } | Select-Object -ExpandProperty media_id)
    }
    # ... repeat for other sections
  )
}

$crossrefs | ConvertTo-Json | Set-Content 'C:\CIC_MEDIA_LIBRARY\CIC\metadata\treatment_crossref_index.json'
```

#### **3d: Final Validation**
```powershell
# Count what we have
$inventory = Import-Csv 'C:\CIC_MEDIA_LIBRARY\CIC\metadata\master_media_inventory.csv'
Write-Host "Total media: $($inventory.Count)"
Write-Host "With media IDs: $($inventory | Where-Object { $_.media_id } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "Pre-cleared: $($inventory | Where-Object { $_.rights_status -eq 'pre_cleared' } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "Needs clearance: $($inventory | Where-Object { $_.rights_status -eq 'needs_clearance' } | Measure-Object | Select-Object -ExpandProperty Count)"

# Verify no orphaned sidecars
$mediaWithoutJSONs = Get-ChildItem 'C:\CIC_MEDIA_LIBRARY\CIC\media\By_Topic' -Recurse -Filter '*.jpg' | 
  Where-Object { -not (Test-Path ($_.FullName -replace '\.jpg$', '.json')) }

if ($mediaWithoutJSONs.Count -eq 0) {
  Write-Host "✓ All media have sidecars" -ForegroundColor Green
} else {
  Write-Host "⚠ $($mediaWithoutJSONs.Count) media missing sidecars" -ForegroundColor Yellow
}
```

---

## FINAL OUTPUT: COMPLETE DAM

After all steps:

```
C:\CIC_MEDIA_LIBRARY\CIC\
├─ media/
│  ├─ By_Topic/
│  │  ├─ 1-Willow_Run_Bomber_Plant/ [~150 images from Kroll + ingest]
│  │  ├─ 2-CESOR_Charles_Emil_Sorensen/ [~50 images]
│  │  ├─ 3-M_Y_Helene_Yacht/ [~50 images]
│  │  ├─ 4-Harry_Bennett_Service_Department/ [~20 images]
│  │  ├─ 5-Labor_Relations_1940s/ [~30 images]
│  │  ├─ 6-Royal_Correspondence_Denmark/ [~10 images]
│  │  ├─ 7-Cuba_Research/ [TBD]
│  │  ├─ 8-Virgin_Islands_Research/ [TBD]
│  │  ├─ 9-Willys_Overland_History/ [~25 images]
│  │  └─ 99-Uncategorized/ [remainder]
│  ├─ By_Type/
│  │  ├─ Photographs/ [symbolic links to all images]
│  │  ├─ Documents/ [Word, PDF files]
│  │  └─ [other types]
│  └─ By_Source/
│     ├─ Kroll_Archive/ [all Kroll media]
│     ├─ Family_Collection/ [family photos]
│     └─ [other archives]
├─ metadata/
│  ├─ master_media_inventory.csv [870+ rows, all indexed]
│  ├─ search_index.json [searchable by topic/type/archive]
│  ├─ treatment_crossref_index.json [all media linked to Treatment sections]
│  └─ folder_to_topic_mapping.json [Drive → DAM mapping]
├─ research_logs/
│  ├─ 1-Willow_Run_log.md + _index.json
│  ├─ 2-CESOR_Biography_log.md + _index.json
│  ├─ [9 topic logs total]
│  └─ research_logs_index.json
├─ versions/
│  ├─ Treatment_v13_master.md [AUTHORITATIVE]
│  └─ treatment_sections_reference.json
└─ operations/
   ├─ master_media_inventory.csv [synced from metadata/]
   ├─ marketing_readiness.json
   └─ follow_ops_checklist.json
```

---

## TIMELINE: DAILY BATCH APPROACH (RECOMMENDED)

**Day 1 (Tuesday):** Step 1 + Test Batch
```powershell
# Copy everything from Drive (30 min)
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-copy-from-drive.ps1'

# Ingest just Helene (test, 30 min)
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Helene*"

# Verify: should have ~50 media IDs assigned
Import-Csv 'C:\CIC_MEDIA_LIBRARY\CIC\metadata\master_media_inventory.csv' | Measure-Object
```

**Day 2 (Wednesday):** Kroll + Later Life
```powershell
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Kroll*"
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Later*"
```

**Day 3 (Thursday):** Documents + Willys
```powershell
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Willys*"
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Documents*"
```

**Day 4 (Friday):** Integration + Validation
```powershell
# Copy Treatment v13
Copy-Item 'G:\My Drive\Cast Iron Charlie — Documentary Project\Documents\Treatment\CastIronCharlie_Treatment_v13_20260523.txt' `
  -Destination 'C:\CIC_MEDIA_LIBRARY\CIC\versions\Treatment_v13_master.md'

# Update research logs
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\maintain-research-log.ps1' -Topic all

# Run operations + marketing curation
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\cic-follow-ops.ps1' -EmailSummary $true
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\curate-cic-marketing-assets.ps1'
```

**Result:** Full DAM online with 870+ items indexed, searchable, and ready.

---

## NEXT STEPS AFTER BULK INGESTION

1. **Weekly:** Run `curate-cic-marketing-assets.ps1` to refresh social calendar + pitch deck
2. **Bi-weekly:** Run `cic-follow-ops.ps1` to surface Dad questions + gaps + readiness
3. **As needed:** New batch from Kroll → ingest via single batch run

---

## SUPPORT

- **Architecture:** Read `CIC_DAM_SYSTEM.md`
- **Detailed scripts:** Each `.ps1` has detailed comments
- **Folder mapping:** `metadata/folder_to_topic_mapping.json`
- **Troubleshooting:** See sections above

---

**END OF BULK INGESTION GUIDE**

*Ready to ingest 777 images + 92 documents into Cast Iron Charlie DAM*

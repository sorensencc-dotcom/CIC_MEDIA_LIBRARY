# CAST IRON CHARLIE — MIGRATION GUIDE
## Moving 67 Existing Images + Treatment into DAM

**Status:** Ready to execute  
**Date:** 2026-06-06  
**Owner:** Christopher Sorensen  

---

## OVERVIEW

You have 67 images across 4 batches + Treatment v13 + research logs in various formats. This guide walks through moving them into the DAM structure in a **controlled, non-destructive pass**.

**Total time estimate:** 3-4 hours (can break into sessions)

---

## PRE-MIGRATION CHECKLIST

- [ ] Verify all folder structure created:
  ```powershell
  ls C:\CIC_MEDIA_LIBRARY\CIC\
  ```
  Should show: scripts/, media/, metadata/, research_logs/, operations/, versions/, logs/, migration/

- [ ] Verify all six skills exist:
  ```powershell
  ls C:\CIC_MEDIA_LIBRARY\CIC\scripts\*.ps1
  ```
  Should show: ingest, classify, organize, maintain-research-log, curate, follow-ops

- [ ] Back up originals:
  ```powershell
  Copy-Item -Path 'C:\Users\soren\Downloads\TEmp' -Destination 'C:\Users\soren\Downloads\TEmp_BACKUP' -Recurse
  ```

---

## MIGRATION PHASES

### **PHASE 1: IMAGE MIGRATION (Batch 1–4)**

Per the `MASTER_IMAGE_INDEX_20260523`, organize images by destination:

#### **Batch 1 (19 images) → 3 destinations**

**Destination 1: Photographs/Family Archive/**
- IMG_1512: Sorensen_CharlesMitchel_c1950s_001.jpg
- IMG_1513: Sorensen_CharlesMitchel_c1952-53_002.jpg
- IMG_1519: MY_Helene_AtDock_WithBunting_1930s.jpg

**Steps:**
1. Rename each image per manifest (standardize naming)
2. Create sidecar JSON for each:
   ```json
   {
     "metadata_version": "1.0",
     "filename": "sorensen_charles_mitchel_c1950s_001.jpg",
     "file_extension": ".jpg",
     "sha256_hash": "[GENERATE WITH Get-FileHash]",
     "date_ingested": "2026-06-06T14:00:00Z",
     "classification": {
       "type": "Photograph",
       "primary_topic": "2-CESOR_Charles_Emil_Sorensen",
       "subtopic": "Biographical_Family_Archive",
       "documentary_significance": "Medium",
       "historical_date": "1950-01-01",
       "historical_date_confidence": "estimated"
     },
     "source_metadata": {
       "archive_origin": "Kroll Archive",
       "batch_id": "Batch_001",
       "rights_status": "pre_cleared",
       "attribution_required": false
     }
   }
   ```

3. Copy image + sidecar to:
   ```
   C:\CIC_MEDIA_LIBRARY\CIC\media\By_Topic\2-CESOR_Charles_Emil_Sorensen\Biographical_Family_Archive\
   ```

4. Run link creation:
   ```powershell
   New-Item -ItemType SymbolicLink `
     -Path 'C:\CIC_MEDIA_LIBRARY\CIC\media\By_Type\Photographs\sorensen_charles_mitchel_c1950s_001.jpg' `
     -Value 'C:\CIC_MEDIA_LIBRARY\CIC\media\By_Topic\2-CESOR_Charles_Emil_Sorensen\Biographical_Family_Archive\sorensen_charles_mitchel_c1950s_001.jpg'
   ```

**Destination 2: Documents/Source_Articles/**
- IMG_1508: AutoNews_Oct1_1945_Bennett_Bugas.jpg
- IMG_1505: ConsolidatedAircraft_Memo_Aug4_1941_B24D_Transport.jpg
- [3 more document images]

**Destination 3: Research/Willow_Run_Logistics/**
- IMG_1510: MilitaryFord_Truck_W0101360_Component_Transport.jpg
- [5 more truck/logistics photos]

#### **Batch 2 (8 images) → Research/Willow_Run_Production/**
All KD truck + Kroll essay images
- Copy, create sidecars, organize

#### **Batch 3 (20 images) → Research/Willow_Run_Production/**
Riveting + Women workforce
- Copy, create sidecars, organize

#### **Batch 4 (20 images) → 3 destinations**
Exit timeline + Royal correspondence
- Distribute per manifest

### **PHASE 2: MEDIA ID ASSIGNMENT**

Once all 67 images are in By_Topic folders with sidecars:

```powershell
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\organize-cic-media-library.ps1' `
  -InputPath 'C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified' `
  -Validate $true
```

**This will:**
- Assign media IDs (CIC-WR-1944-001, CIC-CE-1938-001, etc.)
- Create By_Type + By_Source symbolic links
- Generate master_media_inventory.csv
- Update search_index.json

### **PHASE 3: RESEARCH LOG MIGRATION**

#### **Willow Run Log**
Copy from `C:\Users\soren\Downloads\TEmp\Kroll_TalesFromBomberPlant_COMPLETE.txt` to:
```
C:\CIC_MEDIA_LIBRARY\CIC\research_logs\1-Willow_Run_log.md
```

Format as Markdown with entry sections:

```markdown
# WILLOW RUN BOMBER PLANT — RESEARCH LOG

## PART 1: THE LONG ROAD OUT
### KD Knockdown Logistics, March 1942 – August 1944

1,094 knock-down (KD) kits shipped...
[rest of narrative]

## Media Evidence
- CIC-WR-1944-001: [description]
- CIC-WR-1944-002: [description]
```

#### **Other Topic Logs**
- CESOR Biography: Create or import from existing sources
- Labor Relations: Populate with UAW/strike materials
- Cuba Research: Create stub (awaiting content)
- Virgin Islands: Create stub (awaiting content)
- Willys: Populate from any existing Willys research

Run:
```powershell
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\maintain-research-log.ps1' -Topic all
```

**This will:**
- Generate structured index JSON for each log
- Extract facts and media ID links
- Create structured_index.json files

### **PHASE 4: TREATMENT MIGRATION**

1. Copy Treatment v13 from Downloads:
   ```powershell
   Copy-Item -Path 'C:\Users\soren\Downloads\TEmp\CastIronCharlie_Treatment_v13_20260523.txt' `
     -Destination 'C:\CIC_MEDIA_LIBRARY\CIC\versions\Treatment_v13_master.md'
   ```

2. Rename to .md for Markdown formatting (optional)

3. Create `treatment_sections_reference.json`:
   ```json
   {
     "treatment_version": "v13",
     "sections": [
       {
         "section_name": "The Engineering Mind",
         "linked_topics": [
           "1-Willow_Run_Bomber_Plant/Riveting_Production_Women_Workforce",
           "1-Willow_Run_Bomber_Plant/KD_Knockdown_Logistics"
         ]
       },
       {
         "section_name": "The Parallel Power Structure",
         "linked_topics": [
           "1-Willow_Run_Bomber_Plant/KD_Knockdown_Logistics",
           "4-Harry_Bennett_Service_Department"
         ]
       },
       {
         "section_name": "The Pivot & Decline",
         "linked_topics": [
           "2-CESOR_Charles_Emil_Sorensen/March_1944_Departure_Timeline"
         ]
       },
       {
         "section_name": "The Royal Dimension",
         "linked_topics": [
           "6-Royal_Correspondence_Denmark"
         ]
       }
     ]
   }
   ```

4. Manually review sidecars to ensure treatment_cross_refs are populated correctly

### **PHASE 5: VALIDATION & RECONCILIATION**

```powershell
# Check for missing sidecars
Get-ChildItem 'C:\CIC_MEDIA_LIBRARY\CIC\media\By_Topic' -Recurse -Filter '*.jpg' | 
  Where-Object { -not (Test-Path ($_.FullName -replace '\.jpg$', '.json')) }

# Verify all media IDs assigned
$inventory = Import-Csv 'C:\CIC_MEDIA_LIBRARY\CIC\metadata\master_media_inventory.csv'
$inventory | Where-Object { $_.media_id -eq $null } | Measure-Object

# Test search index
$index = Get-Content 'C:\CIC_MEDIA_LIBRARY\CIC\metadata\search_index.json' | ConvertFrom-Json
$index.total_media_count  # Should equal 67
```

---

## DETAILED MIGRATION STEPS

### **Step 1: Organize Batch 1 Images**

Open file explorer:
```
C:\Users\soren\Downloads\TEmp\MASTER_IMAGE_INDEX_20260523
```

For each image in Batch 1:

1. **Get original filename and destination**
   ```
   Img 1: IMG_1512 → Sorensen_CharlesMitchel_c1950s_001.jpg 
          Destination: Photographs/Family Archive/
   ```

2. **Copy from Downloads to staging:**
   ```powershell
   Copy-Item 'C:\Users\soren\Downloads\TEmp\[original_img_path]' `
     -Destination 'C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\[new_name].jpg'
   ```

3. **Generate SHA-256 hash:**
   ```powershell
   (Get-FileHash -Path 'C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\[new_name].jpg' -Algorithm SHA256).Hash
   ```

4. **Create sidecar JSON** (use template above)
   ```powershell
   $sidecar = @{ ... } | ConvertTo-Json | Set-Content '..\[new_name].json'
   ```

5. **Create By_Topic folder structure:**
   ```powershell
   New-Item -ItemType Directory -Path `
     'C:\CIC_MEDIA_LIBRARY\CIC\media\By_Topic\2-CESOR_Charles_Emil_Sorensen\Biographical_Family_Archive' `
     -Force
   ```

6. **Move media + sidecar to By_Topic:**
   ```powershell
   Move-Item 'C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\[new_name].*' `
     -Destination 'C:\CIC_MEDIA_LIBRARY\CIC\media\By_Topic\2-CESOR_Charles_Emil_Sorensen\Biographical_Family_Archive'
   ```

### **Steps 2–4: Repeat for Batches 2–4**

Same process, but with different topics + subtopics per the MASTER_IMAGE_INDEX.

### **Step 5: Run Organize Script**

Once all 67 images are manually organized into By_Topic structure:

```powershell
# Option A: Process images still in _Inbox/classified
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\organize-cic-media-library.ps1'

# Option B: Scan existing By_Topic structure and assign IDs
# (May require script modification to handle already-organized images)
```

---

## EXPECTED OUTPUTS AFTER MIGRATION

```
C:\CIC_MEDIA_LIBRARY\CIC\
├── media/
│   ├── By_Topic/
│   │   ├── 1-Willow_Run_Bomber_Plant/
│   │   │   ├── 1944_Production_Logistics/
│   │   │   │   ├── CIC-WR-1944-001.jpg
│   │   │   │   ├── CIC-WR-1944-001.json
│   │   │   │   └── [42 more Willow Run images]
│   │   ├── 2-CESOR_Charles_Emil_Sorensen/
│   │   │   ├── Biographical_Family_Archive/
│   │   │   │   ├── CIC-CE-1938-001.jpg
│   │   │   │   └── CIC-CE-1938-001.json
│   │   │   └─ [3 more CESOR images]
│   │   └── [other topics with assigned media IDs]
│   ├── By_Type/
│   │   ├── Photographs/ → [symlinks]
│   │   ├── Documents/ → [symlinks]
│   │   ├── Newspapers/ → [symlinks]
│   │   └── [other types]
│   └── By_Source/
│       ├── Kroll_Archive/
│       │   ├── Batch_001/ → [symlinks]
│       │   ├── Batch_002/ → [symlinks]
│       │   ├── Batch_003/ → [symlinks]
│       │   └── Batch_004/ → [symlinks]
│       └── [other sources]
├── metadata/
│   ├── master_media_inventory.csv [67 rows]
│   ├── search_index.json [indexed by topic, type, archive]
│   └── treatment_crossref_index.json [updated]
├── research_logs/
│   ├── 1-Willow_Run_log.md [narrative]
│   ├── 1-Willow_Run_index.json [structured]
│   ├── 2-CESOR_Biography_log.md
│   ├── 2-CESOR_Biography_index.json
│   └── [6 more topic logs]
└── versions/
    ├── Treatment_v13_master.md [MIRROR from Drive]
    └── treatment_sections_reference.json [cross-refs]
```

---

## VALIDATION CHECKLIST

After migration completes:

- [ ] **67 media files** in By_Topic structure
- [ ] **67 sidecar JSON** files (one per media)
- [ ] **master_media_inventory.csv** has 67 rows
- [ ] **All media IDs unique** (CIC-WR-1944-001 through -043, CIC-CE-1938-001 through -008, etc.)
- [ ] **All treatment_cross_refs** populated in sidecars
- [ ] **All rights_status** assigned (pre_cleared for Kroll/MFM/Benson, needs_clearance for others)
- [ ] **Research logs** have 9 topic files (1–9) + index JSONs
- [ ] **Treatment_v13_master.md** in versions/ folder
- [ ] **search_index.json** indexes all 67 items

**Test search:**
```powershell
$index = Get-Content 'C:\CIC_MEDIA_LIBRARY\CIC\metadata\search_index.json' | ConvertFrom-Json
$index.indexes.by_topic.'1-Willow_Run_Bomber_Plant'.Count  # Should show 42 items
```

---

## POST-MIGRATION: FIRST DAM RUN

Once everything is organized and indexed:

```powershell
# 1. Update research logs with auto-generated structured index
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\maintain-research-log.ps1' -Topic all

# 2. Curate marketing assets
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\curate-cic-marketing-assets.ps1'

# 3. Assess follow-ups
& 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\cic-follow-ops.ps1' -EmailSummary $true
```

**Outputs:**
- Social media calendar for next 4 weeks (2-3 posts/week)
- Pitch deck asset pack (best 30–50 images)
- Grant application bundles (NEH, CPB, festivals)
- Ops checklist (rights, gaps, Dad questions, readiness scores)

---

## TROUBLESHOOTING

### **"Symlink creation failed"**
- Windows requires admin privileges for symlinks
- Workaround: Scripts fall back to copying files instead
- OK for local work; won't affect functionality

### **Media ID sequence out of order**
- Check `metadata/media_versioning.json`
- Each topic code (WR, CE, BENNETT, etc.) has its own sequence
- Incrementing is atomic per topic

### **Sidecar JSON validation fails**
- Use online JSON validator to check syntax
- Ensure all required fields are present
- Check for special characters in strings (escape quotes)

### **Search index doesn't include all images**
- Re-run `organize-cic-media-library.ps1`
- Check that all images have complete sidecars
- Verify media_id field is populated in all sidecars

---

## TIME ESTIMATE

| Phase | Duration | Notes |
|-------|----------|-------|
| Pre-migration checks | 15 min | Verify folder structure, backups |
| Batch 1 migration | 30 min | 19 images, manual rename + copy |
| Batch 2 migration | 20 min | 8 images |
| Batch 3 migration | 30 min | 20 images |
| Batch 4 migration | 30 min | 20 images |
| Media ID assignment | 10 min | Run organize script |
| Research log migration | 20 min | Copy + format logs |
| Treatment migration | 15 min | Copy + create cross-refs |
| Validation | 15 min | Run checks + verify outputs |
| **TOTAL** | **3–4 hours** | Can break into sessions |

---

## QUESTIONS?

Refer to:
- `CIC_DAM_SYSTEM.md` — Full architecture + schemas
- `scripts/*.ps1` — Each skill has detailed comments
- `metadata/schema.json` — All JSON schemas defined

---

**END OF MIGRATION GUIDE**

*Cast Iron Charlie — Digital Asset Management  
Ready to migrate 67 images + Treatment into the DAM system*

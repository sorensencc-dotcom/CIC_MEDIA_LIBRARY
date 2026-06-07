# Entity Relationship Graph Summary

**Generated:** 2026-06-06 21:23
**Domain:** documentary
**Source:** C:\CIC_MEDIA_LIBRARY\CIC\media\_test_ocr

## Counts

| Type | Count |
|------|-------|
| Person | 7 |
| Place | 10 |
| Organization | 5 |
| Document | 3 |
| **Total nodes** | **25** |
| **Total edges** | **135** |

## People

**Charles Emil Sorensen**
- Relationships: born_in → Odense, Denmark; lived_in → Detroit; employed_by → Ford Motor Company; reported_to → Henry Ford; adversarial_with → Harry Bennett; corresponded_with → King Frederik X; employed_by → Willys-Overland Motors
- Evidence: birth_certificate_1901.jpg, ford_memo_1943.jpg, fortune_article_1944.jpg

**Harry Bennett**
- Relationships: employed_by → Ford Motor Company; reported_to → Henry Ford
- Evidence: ford_memo_1943.jpg, fortune_article_1944.jpg

**Henry Ford**
- Relationships: lived_in → Dearborn; founded → Ford Motor Company
- Evidence: ford_memo_1943.jpg, fortune_article_1944.jpg

**Jens Christian Sorensen**
- Relationships: spouse_of → Mette Kirstine Nielsen; parent_of → Lars Emil Sorensen
- Evidence: birth_certificate_1901.jpg

**King Frederik X**

**Lars Emil Sorensen**
- Evidence: birth_certificate_1901.jpg

**Mette Kirstine Nielsen**
- Relationships: parent_of → Lars Emil Sorensen
- Evidence: birth_certificate_1901.jpg

## Key Relationships

- **Harry Bennett** → [employed_by] → **Ford Motor Company** (100% confidence)
- **Charles Emil Sorensen** → [employed_by] → **Ford Motor Company** (100% confidence)
- **Charles Emil Sorensen** → [reported_to] → **Henry Ford** (100% confidence)
- **Henry Ford** → [founded] → **Ford Motor Company** (100% confidence)
- **Mette Kirstine Nielsen** → [parent_of] → **Lars Emil Sorensen** (95% confidence)
- **Jens Christian Sorensen** → [parent_of] → **Lars Emil Sorensen** (95% confidence)
- **Harry Bennett** → [reported_to] → **Henry Ford** (90% confidence)
- **Charles Emil Sorensen** → [employed_by] → **Willys-Overland Motors** (90% confidence)
- **Charles Emil Sorensen** → [adversarial_with] → **Harry Bennett** (85% confidence)
- **Jens Christian Sorensen** → [spouse_of] → **Mette Kirstine Nielsen** (80% confidence)

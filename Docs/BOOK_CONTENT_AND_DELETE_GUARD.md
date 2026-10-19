# Book content & book-member delete guard

_Added 2026-10-17._

## 1. A recipe in a book is never deleted

Rule: once a recipe's UUID is in any `Book.recipeIDs`, no automatic, bulk or
everyday action deletes it. Removing it **from** a book is always allowed.

Central logic: `Reczipes2/Utilities/BookMembershipGuard.swift`

| API | Meaning |
|---|---|
| `BookMembershipGuard(context:)` / `(books:)` / `(bookContents:)` | build the recipe-id → book-names map (fails safe: if books can't be fetched, everything is protected) |
| `isProtected(id)` | id is in some book |
| `bookNames(for:)` | names of the books containing it |
| `canRemoveDuplicate(copy, keeping:)` | a duplicate copy may go only if it is in no book (or is the same UUID as the kept row) |
| `refusalMessage(...)` | "'X' is in 'Book'. Remove it from 'Book' first." |
| `forceDeleteBookMember(_:typedConfirmation:in:)` | the ONLY book-member delete; removes the id from every book, then deletes |

### Every RecipeX delete path and its guard

| Path | Behaviour now |
|---|---|
| Recipe list swipe / context menu "Delete Recipe" (`ContentView.deleteRecipe`) | refuses with alert naming the books |
| Launch duplicate auto-clean (`ContentView.autoCleanDuplicates`) | book copy preferred as keeper; book members skipped + logged |
| Post-sync duplicate auto-clean (`CloudKitDuplicateMonitor.checkForDuplicates`) | same |
| Duplicate Detector: Remove Copy / Keep This / Merge Exact Copies (`DuplicateRecipeDetectorView.mergeCopy`) | only copies in no book are removed; groups where every copy is in a book are shown "Protected — all in books" and cannot be merged |
| Legacy `RecipeDuplicateDetectorView` (preview only) | guarded the same way |
| Maintenance → Remove Duplicate Recipes (`DatabaseDuplicateCleanupView`) | rows share one UUID; one row always survives, so books still resolve (`canRemoveDuplicate`) |
| Empty Recipe Cleanup (`EmptyRecipeCleanupView`) | no longer strips recipes out of books; book members are skipped and reported |
| Backup restore, `importBackupX` (gives the restored copy a NEW id) | a book member is not overwritten (skipped) |
| Backup restore, `importBackup` (same id) | allowed: same-id replacement, books keep resolving |
| Recipe Extractor "Undo Save" | skipped if the new recipe is somehow already in a book |
| Deleting a **book** (`RecipeBooksView.deleteBook`) | used to delete every recipe in the book — now deletes only the book record |
| `.recipebook` import replace (`RecipeBookImportService`, `RecipeBookExportService`) | deletes the old Book record only (never recipes) — unchanged |
| `CloudKitSharingService`, `OrphanedDataCleanupUtility`, `LinkImportService`, `VersionHistoryService` | delete tracking / cache / link / history models only — no RecipeX |

### The admin path

Settings → Sharing → **Manage CloudKit Recipes** → **Delete a Book Recipe (Admin)…**
(`BookRecipeAdminDeleteView`). Lists recipes that are in books, shows which
books contain the chosen one, requires the exact title to be typed, takes down
its public CloudKit copy, removes it from those books, then deletes it.

## 2. Book content

Model (`Book.swift`; pictures are `BookPicture` records since §3, the rest is JSON inside existing `Book` attributes):

* `BookImage` gained optional `kind` ("cover" / "interior"; nil = interior),
  `sourcePage`, `linkedRecipeIDs`, `sourceFile`. Several covers are allowed;
  `setImagesUpdatingPrimaryCover` keeps `coverImageData` = first cover.
* `BookGlossaryEntry` gained optional `localName`, `sourcePage`.
* `BookSection` rows: `itemType` "heading" (fresh UUID, `level` 0 chapter /
  1 sub-heading), "recipe", "image", "glossary", "index"; optional `sourcePage`.
* Pictures are downscaled on add to ≤1600 px long side, JPEG 0.7
  (`BookImageProcessing`).

Viewer (`BookDetailView` + `BookContentViews.swift`): segmented
Recipes | Contents | Pictures | Glossary | Index.

* **Contents** – stored rows filtered to current members/pictures; members not
  in the contents are appended under "More Recipes"; plain recipe order if no contents.
* **Pictures** – covers, then interior, captions, tap to zoom (pinch / double-tap).
* **Glossary** – term — local name — definition, searchable; tab hidden when empty.
* **Index** – generated at view time from the book's CURRENT recipes,
  alphabetical (`BookIndexBuilder`). No page numbers are stored.

Edit Book: Covers & Pictures (add several, Cover/Interior, caption, move,
delete) and Glossary (import JSON, remove).

### Import Book Package…

Book → More → **Import Book Package…** (macOS `NSOpenPanel` via
`MacFilePicker.pickFolder`, iOS `fileImporter`). Reads
`book_structure.json`, `glossary.json`, `recipe_index.csv`,
`Book_Images/captions.json` + pictures (`BookPackageImporter.swift`).

* Recipes match by normalised title (case/accents/punctuation-insensitive,
  also the part before "(") — book members first, then the whole library.
* Matched recipes are put first in section order; existing members are kept
  after them. Nothing is removed.
* Contents rows are rebuilt: chapter / sub-heading headings, recipes,
  pictures (chapter pictures placed after the last recipe on or before their page).
* Pictures from `captions.json` (`01_*`, `07_*` = covers); caption = title + caption text;
  `linkedRecipeIDs` from the NN ids. Re-importing replaces pictures with the same file name.
* Glossary stored when present. `recipe_index.csv` is only used to map NN ids to
  titles — the app's index is generated.
* A summary lists unmatched titles and the package's "missing" notes.

### Export / sync

* `.bookbackup` (`BookBackup`) now carries `imagesData`, `glossaryData`,
  `tableOfContentsData` (optional — old backups still restore).
* `.recipebook` (`ExportableBook`) carries `images` (when exporting with
  images), `glossary`, `tableOfContents`; imports remap recipe ids.
* `BookSyncService` already sends `imagesJSON` / `glossaryJSON` /
  `tableOfContentsJSON`; new struct fields ride along.
* Duplicate-book merge backfills pictures / glossary / contents.

## 3. Pictures as records (decided and done, 2026-10-17)

The size concern (inline base64 pictures in `Book.imagesData`, 2–4 MB per book,
too big for a public record, re-uploaded on every private-sync edit) is fixed by
storing **one record per picture**.

### Local model — `Models/BookPicture.swift`

`@Model BookPicture` (CloudKit-compatible: all optional, no unique, no relationships):
`id` (= the BookImage id), `bookID` (plain UUID, not a relationship), `kind`
("cover"/"interior"), `title`, `caption`, `sortOrder`, `sourcePage`, `sourceFile`,
`linkedRecipeIDsData` (JSON [UUID]), `@Attribute(.externalStorage) imageData`,
`imageHash` (SHA256), `dateAdded`, `dateModified`. Registered in every model
list in `ModelContainerManager` (same pattern as `CachedSharedMeal` — added to
the container, not to `SchemaV4`).

* `Book.imagesData` now holds **metadata only** (BookImage entries with empty
  `imageData`), a few hundred bytes per picture. Old builds still decode it.
* `Book.images` / `coverImages` / `interiorImages` read rows through
  `book.modelContext`; `setImages(_:in:)` / `setImagesUpdatingPrimaryCover(_:in:)`
  write rows (upsert by id, delete the rest; unchanged bytes are not rewritten,
  compared by hash) and rewrite the metadata JSON.
* `coverImageData` = first cover, downscaled to ≤800 px JPEG 0.7 (list
  thumbnails, older clients, `coverImage` asset).
* `BookPictureStore` – fetch / images / count / replace / add / delete / reorder /
  deleteAll / `deleteBook` / `metadataJSON`. `isAvailable(in:)` is false for
  preview/test containers built with only `Book.self`; then pictures stay inline.

### Launch migration — `BookPictureMigration`

`ContentView.handleOnAppear` runs `BookPictureMigration.migrateAll(in:)` after
the duplicate auto-clean, **every launch** (books from a device on an older build
can still arrive with inline bytes). For each Book whose `imagesData` has entries
with bytes: create a row per picture unless a row with the same id or
`sourceFile` already exists for that book (idempotent), give a byte-less row its
bytes back, then rewrite `imagesData` as metadata only; save per book. JSON that
can't be decoded is **left in place** and logged — nothing is dropped. Also used
by `.bookbackup` restore and by the duplicate-book merge before deleting a copy.

### Delete / merge

* Deleting a book (`RecipeBooksView.deleteBook`, community-book removal, backup
  overwrite) uses `BookPictureStore.deleteBook`: deletes the Book and its picture
  rows (rows are kept if another Book row with the same id remains). Recipes are
  never deleted.
* Duplicate-book merge: copies share the book id, so the rows already belong to
  the kept book; inline pictures on the copy are migrated before it is deleted.
* `.recipebook` replace import keeps the same book id; its rows are replaced by
  the imported pictures.

### Package import / Edit Book

Both write rows (`setImagesUpdatingPrimaryCover(_:in:)`); a package re-import
reuses the picture id of the same `sourceFile`, so it replaces instead of duplicating.

### Export / import files

`.bookbackup` (`BookBackup.imagesData`) and `.recipebook` (`ExportableBook.images`)
still carry the **bytes** (read from the rows). Import recreates rows for the
(possibly new) book id; picture ids are kept (rows are scoped by book id, so a
"keep both" copy can reuse them), recipe ids are remapped in `linkedRecipeIDs`
and contents rows.

### Public CloudKit — `Models/BookPicturePublisher.swift`

"Share / Update Public Copy" (`CloudKitSharingService.shareRecipeBook`, record
type `SharedRecipeBook`, the one the website reads) and `BookSyncService`
(record type `Book`) publish each picture as its own **`SharedBookPicture`**
record (image = CKAsset, ≤1600 px JPEG; bytes re-uploaded only when `imageHash`
changed), delete picture records that are no longer listed, and put only
metadata in the book record:

* `SharedRecipeBook.bookData` (JSON of `CloudKitRecipeBook`) gained optional
  `images` ([BookPictureMetadata]), `tableOfContents`, `glossary` (no schema
  change — `bookData` is a String). If bookData passes 250 KB, contents and then
  glossary are dropped from the public copy.
* `Book.imagesJSON` = [BookPictureMetadata].

`BookPictureMetadata` = `{ id, title, caption, imageData: "" , order, dateAdded,
kind, sourcePage, linkedRecipeIDs, pictureRecordName, imageHash }` (keeps
BookImage's keys so old decoders still work).

Record `SharedBookPicture`, name `BookPicture_<BOOKUUID>_<PICTUREUUID>`:

| field | type | |
|---|---|---|
| bookID | String | book UUID (uppercase) — **Queryable** |
| bookRecordName | String | SharedRecipeBook / Book record name |
| pictureID | String | = metadata `id` |
| kind | String | cover / interior |
| title, caption, sourcePage | String | |
| order | Int64 | |
| linkedRecipeIDs | String (list) | omitted when empty |
| image | Asset | JPEG |
| imageHash | String | SHA256 of the stored bytes |
| sharedBy | String | publisher's user record name |

Unshare / delete / ghost cleanup delete the picture records too (names from the
book record + a `bookID` query). Picture failures never fail the book share; a
picture that didn't save is listed without `pictureRecordName`.

Receiving: `syncCommunityBooksToLocal` → `applyPublishedBookContent` stores
contents/glossary and downloads only pictures whose `imageHash` differs from the
local row, into BookPicture rows; `BookSyncService.downloadBook` does the same.

**Production schema deploy needed before shipping**: record type
`SharedBookPicture` with the fields above (create in Development by running a
share, or by hand), index `bookID` QUERYABLE and `recordName` QUERYABLE
(the website lists all records of a type), then *Deploy Schema Changes* to
Production. Until then picture saves fail in Production (logged; books still share
without pictures).

### Website contract (web/ session)

1. Book: `SharedRecipeBook.bookData.images[]` — `{ id, title, caption, kind,
   order, sourcePage, linkedRecipeIDs, pictureRecordName }` (no bytes). Same
   fields as today plus `pictureRecordName`; `bookImages` (asset list) is **not**
   written.
2. Image URL: look up the records named by `pictureRecordName` —
   `POST /database/1/{container}/{env}/public/records/lookup` with
   `{ "records": [{ "recordName": "BookPicture_…" }], "desiredKeys": ["image","pictureID"] }`
   — or query `{ "recordType": "SharedBookPicture", "filterBy": [{ "fieldName": "bookID",
   "comparator": "EQUALS", "fieldValue": { "value": "<BOOK UUID>" } }] }`
   (or `queryAll('SharedBookPicture')` and group by `bookID`).
   `fields.image.value.downloadURL` with `${f}` replaced by a file name, as for
   `coverImage`. Download URLs expire; fetch them per refresh, don't store them.
3. Match picture to metadata by `fields.pictureID.value` == `images[].id`
   (compare upper-case). Skip metadata entries without a picture record.
4. `bookData.tableOfContents` rows of `itemType: "image"` have `itemID` = picture id.

## 4. Tests

New files (picked up automatically — `Reczipes2Tests` is a
`PBXFileSystemSynchronizedRootGroup`):

* `Reczipes2Tests/BookMembershipGuardTests.swift`
* `Reczipes2Tests/BookContentTests.swift` (incl. picture migration, metadata size, record lifecycle)

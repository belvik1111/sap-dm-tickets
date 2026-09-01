# YRST_GH_LCOND_DEAKT – Review-Fixes 2026-08-25

## Hotfix 2026-09-01 – SAPSQL_STMNT_TOO_LARGE in SELECT_ARTICLES_WITH_STOCK

Laufzeitfehler `SAPSQL_STMNT_TOO_LARGE` (`CX_SY_OPEN_SQL_DB`) in
`SELECT_ARTICLES_WITH_STOCK`. Ursache: der Review-Fix #5 unten
(Kreuzprodukt entfernt) hat `FOR ALL ENTRIES IN it_articles` mit zwei
UND-verknuepften Feldern (`MATNR` und `BUKRS_SEND`) eingefuehrt. Dabei
erzeugt die Datenbankschnittstelle pro Zeile von `it_articles` eine
eigene ODER-verknuepfte Klammer im SQL-Statement
(`(MATNR = 'x1' AND BUKRS = 'y1') OR (MATNR = 'x2' AND BUKRS = 'y2') OR ...`).
Bei entsprechend vielen delisteten Artikel/BuKr-Kombinationen wird die
vom Datenbanksystem erlaubte Statementlaenge ueberschritten.

**Fix**: `SELECT_ARTICLES_WITH_STOCK` verarbeitet `it_articles` jetzt
paketweise (analog `SAVE_UPDATES`/`UPDATE_PACKAGE`); der eigentliche
SELECT wurde nach `SELECT_STOCK_PACKAGE` ausgelagert. Dafuer neue,
bewusst kleinere Konstante `GC_STOCK_CHECK_PACKAGE_SIZE = 500` (TOP-
Include) statt der bestehenden `GC_PACKAGE_SIZE = 10000` – letztere ist
fuer die reine `UPDATE ... FROM TABLE`-Paketierung ausgelegt (keine
OR-Verkettung im SQL) und waere fuer dieses Muster weiterhin zu gross.
Der konkret passende Wert ist datenbankabhaengig und sollte im
Zielsystem mit realistischen Datenmengen verifiziert werden.

## Hotfix 2026-09-01 (2) – Syntaxfehler "GROUP ist hier nicht erlaubt"

Im obigen Hotfix wurde `GROUP BY ... HAVING SUM(...) > 0` weiterhin
zusammen mit `FOR ALL ENTRIES` verwendet. Das ist in Open SQL nicht
erlaubt (`GROUP BY`/`HAVING` duerfen nicht mit `FOR ALL ENTRIES`
kombiniert werden) und fuehrte zum Syntaxfehler.

**Fix**: `SELECT_STOCK_PACKAGE` liest jetzt die Einzelbestandszeilen
ohne Aggregation im SQL (nur `WHERE`, kein `GROUP BY`/`HAVING`) und
bildet die Summe je Artikel/BuKr anschliessend in ABAP per `COLLECT`
auf dem neuen Typ `TY_S_STOCK_QTY`/`TY_T_STOCK_QTY`. Danach werden
Zeilen mit Summe `<= 0` per `DELETE ... WHERE qty <= 0` entfernt –
fachlich identisch zur vorherigen `HAVING`-Bedingung.

## Umgesetzte Fixes (im Code)

1. **Kritisch – Residenzzeiten-Relationen aktiviert** (`..._lcl`, `load_parameters`):
   Das Parsing von `P:RESIDENZ` (Format `<Sender>/<Empfänger>=<Monate>`) war komplett
   auskommentiert, wodurch `mt_residency` immer leer blieb und ausschließlich der
   globale Default (6 Monate) griff. Jetzt aktiv, inkl. robuster Prüfung auf
   unvollständige/nicht-numerische Customizing-Zeilen (werden übersprungen statt
   das Programm abzubrechen).
2. **Konsistenter Werk→Buchungskreis-Join** (`select_delisted_articles`):
   Zuordnung jetzt einheitlich über `T001W` (Werk → Bewertungskreis) → `T001K`
   (Bewertungskreis → BuKr), wie es an anderer Stelle im Programm bereits korrekt
   gemacht wurde. Vorher: direkte Annahme `T001K-BWKEY = MARC-WERKS`, die nur bei
   Bewertung auf Werksebene zufällig stimmt.
3. **Schutz vor ungültigem Intervall** (`build_updates`): LCOND-Sätze mit
   `DATAB > heute` (noch nicht gültig) werden nicht mehr automatisch abgegrenzt
   (das hätte `DATBI < DATAB` erzeugt), sondern protokolliert und übersprungen.
4. **Testlauf-Sichtbarkeit im Batch** (`display`): Das Ausgabeprotokoll zeigt jetzt
   deutlich "Testlauf" bzw. "Produktivlauf" an – Risiko, dass der tägliche
   Hintergrundjob unbemerkt im Testmodus läuft (`P_TEST` ist standardmäßig aktiv).
5. **Kreuzprodukt entfernt** (`select_articles_with_stock`): Bestandsprüfung liest
   jetzt direkt per `FOR ALL ENTRIES` auf den tatsächlichen (BuKr, Artikel)-Paaren,
   statt getrennte Ranges zu bilden und das Kreuzprodukt nachträglich zu filtern.
6. **AUSL_DATUM im Protokoll befüllt** (`add_log_entry`, alle Aufrufe in
   `build_updates`): Auslistungsdatum war im Log-Feld `ausl_datum` nie gesetzt.

## Noch offen / erfordert Entscheidung bzw. Aktion außerhalb des Codes

- **Text-Elemente in SE38 pflegen** (nicht Teil der Includes):
  - `m03` – z.B. "Eintrag beginnt erst in der Zukunft - keine automatische Abgrenzung"
  - `s04` – z.B. "TESTLAUF - es wurden KEINE Änderungen gespeichert!"
  - `s05` – z.B. "Produktivlauf - Änderungen wurden gespeichert."
- **Fachliche Bestätigung DATBI = heute vs. heute − 1** (`build_updates`, Kommentar
  an `ls_new-datbi = sy-datum`): aktuell bleibt der Eintrag am Ausführungstag noch
  gültig und wird erst ab dem Folgetag inaktiv. Falls "ab heute bereits inaktiv"
  gewünscht ist, auf `sy-datum - 1` ändern.
- **Bestandsprüfung MARD vs. I_MATERIALSTOCK**: Anforderung nennt MARD, Code nutzt
  CDS-View `I_MATERIALSTOCK` mit `InventoryStockType = '01'` (frei verwendbarer
  Bestand). Mit Fachbereich klären, ob das ausreicht oder weitere Bestandsarten
  (Qualitätsprüf-/Sperrbestand) berücksichtigt werden müssen, und ob "VZ" wirklich
  alle Werke des abgebenden Buchungskreises meint oder nur eine Teilmenge.
- **Tägliche Einplanung**: rein operativ (SM36/Jobvariante), nicht im Code
  abbildbar. Variante muss `P_TEST` deaktivieren und Pflichtfeld `S_BUKRS` füllen.
- **Objekt-ID für Änderungsbeleg** (`build_object_id`): Zusammensetzung aus
  `bukrs_send + matnr + bukrs_recv + vlfkz + werks + datab` gegen den tatsächlichen
  Schlüssel von `YRST_GH_LCOND` verifizieren (Länge/Eindeutigkeit).
- **Reihenfolge Änderungsbeleg vs. UPDATE/COMMIT** (`save_updates`): Änderungsbelege
  werden aktuell pro Satz geschrieben, bevor das zugehörige Paket per `UPDATE`
  gespeichert wird. Prüfen, ob dies transaktional/atomar zur eigentlichen
  Tabellenänderung erfolgt (insb. bei `ROLLBACK WORK` nach fehlgeschlagenem Update).

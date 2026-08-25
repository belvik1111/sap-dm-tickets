# YRST_GH_LCOND_DEAKT – Review-Fixes 2026-08-25

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

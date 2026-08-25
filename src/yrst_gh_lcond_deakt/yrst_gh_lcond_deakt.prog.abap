*&---------------------------------------------------------------------*
*& Report YRST_GH_LCOND_DEAKT
*&-------------------------------------------------------------------
* dm/fd-Programm-Header
*-------------------------------------------------------------------
* Aufgabe:  S4RFICO-676 PROJ-003950 - Programm zur Bereinigung der Tabelle YRST_GH_LCOND
*&          Abgrenzen (Deaktivieren) von Einträgen der Tabelle
*&          YRST_GH_LCOND für ausgelistete Artikel des abgebenden
*&          Buchungskreises. Änderungsbelege werden ins Änderungsprotokoll der LCOND geschrieben
*&---------------------------------------------------------------------*
* Datum       Kürzel       Name                   Kommentar-Code
*-------------------------------------------------------------------
* 2026-08-18  D0E11032     Viktor Belan           Erstellung
* 2026-08-25  D0E11032     Viktor Belan           Review-Fixes (s. Commit-Historie)
*-------------------------------------------------------------------

INCLUDE yrst_gh_lcond_deakt_top                 .  " Global Data
INCLUDE yrst_gh_lcond_deakt_ssc                 .  " Selektionsbildschirm
INCLUDE yrst_gh_lcond_deakt_lcl                 .  " lokale Klassen
INCLUDE yrst_gh_lcond_deakt_evt                 .  " Events

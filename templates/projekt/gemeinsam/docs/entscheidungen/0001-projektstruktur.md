# 0001: Projektstruktur

Datum: {{DATUM}}

## Lage

Das Projekt beginnt. Es soll über Jahre pflegbar und erweiterbar bleiben, auch wenn ein
lokales Modell den größten Teil des Codes schreibt.

## Entscheidung

Feste Orte: Einstellungen in `config\`, Tests in `tests\`, Dokumentation in `docs\`,
Entscheidungen in `docs\entscheidungen\`. Ein Prüfbefehl für alles: `scripts\Check.ps1`,
seine Schritte stehen in `config\check.json`. Der Git-Hook `.githooks\pre-commit` führt ihn
vor jedem Commit aus.

## Gründe

Wer etwas sucht, findet es am selben Ort wie in jedem anderen Projekt aus dieser Vorlage.
Ein einziger Prüfbefehl ist leicht zu merken, für Mensch und Modell.

## Verworfen

Einstellungen als Konstanten im Code: Sie wären über die Dateien verstreut und nur mit
einer Codeänderung anzupassen.

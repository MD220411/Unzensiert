---
description: Fehler nach festem Ablauf beheben (erst ein Test, der den Fehler zeigt, dann die Korrektur)
argument-hint: <Fehlerbeschreibung, Fehlermeldung oder Bilddatei>
---

Behebe diesen Fehler: $ARGUMENTS

Arbeite die Schritte der Reihe nach ab und überspringe keinen.

1. **Nachstellen.** Lies die Beschreibung genau (bei einem Bild: jeden Aufruf und jede
   Ausgabe darin). Führe genau die genannten Aufrufe aus und halte fest, was geschieht und
   was stattdessen erwartet wird.
2. **Ursache.** Finde die Stelle im Code, die den Fehler verursacht, nicht nur die Stelle,
   an der er sichtbar wird. Prüfe, ob dieselbe Ursache weitere Eingaben betrifft.
3. **Test zuerst.** Schreibe einen Test in die Testdateien des Projekts, der den Fehler
   zeigt, und führe ihn aus: Er muss scheitern.
4. **Korrektur.** Ändere so wenig wie möglich. Baue nichts um, was nicht zum Fehler gehört.
5. **Prüfen.** Der neue Test und alle alten müssen bestehen. Führe danach die Aufrufe aus
   Schritt 1 noch einmal unverändert aus und vergleiche mit dem erwarteten Ergebnis.
6. **Dokumentation.** Beschreibt die README das betroffene Verhalten, passe sie an. Hat das
   Projekt eine `CHANGELOG.md`, ergänze einen Eintrag.
7. **Bericht.** Kurz: Ursache, Korrektur, geänderte Dateien, was offen bleibt.

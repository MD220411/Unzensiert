---
description: Die letzten Änderungen mit frischem Blick prüfen, ohne etwas zu ändern
argument-hint: [was geprüft werden soll, sonst die nicht committeten Änderungen]
---

Prüfe Änderungen an diesem Projekt: $ARGUMENTS

Ändere dabei keine Datei. Ist oben nichts genannt, prüfe die nicht committeten Änderungen
(`git status`, `git diff`); gibt es keine, den letzten Commit (`git show`).

1. **Auftrag.** Stelle fest, was die Änderung leisten soll (Commit-Nachricht, `SPEC.md`,
   Dokumentation, Angabe oben).
2. **Lesen.** Lies jede geänderte Datei ganz, nicht nur die geänderten Zeilen.
3. **Ausführen.** Starte die Tests und, falls vorhanden, den Prüfbefehl des Projekts.
   Probiere die neuen Aufrufe mit einer leeren, einer falschen und einer üblichen Eingabe.
4. **Bewerten.** Suche gezielt nach:
   - Fehlern und Randfällen, die kein Test abdeckt,
   - Verhalten, das vorher ging und jetzt anders ist,
   - festen Werten im Code, die in die Konfigurationsdatei gehören,
   - neuer Logik ohne Test, neuem Verhalten ohne Eintrag in der README,
   - doppeltem Code, Hilfsdateien, auskommentiertem Code.
5. **Bericht.** Eine Liste der Befunde, das Schwerste zuerst, je Befund Datei und Zeile,
   was falsch ist und wie man es zeigt. Trenne Belegtes (ausgeführt, gesehen) von
   Vermutetem. Findest du nichts, sage das und nenne, was du ausgeführt hast.

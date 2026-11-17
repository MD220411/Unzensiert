---
description: Neue Funktion nach festem Ablauf bauen (Anforderung, Plan, Tests, Code, Doku, Prüfung)
argument-hint: <was gebaut werden soll>
---

Baue diese Funktion: $ARGUMENTS

Arbeite die Schritte der Reihe nach ab und überspringe keinen.

1. **Lesen.** README, CLAUDE.md und die betroffenen Dateien. Stelle fest, wo Tests,
   Konfiguration und Dokumentation des Projekts liegen und mit welchem Befehl geprüft wird.
2. **Anforderung.** Schreibe in drei bis acht Punkten auf, woran man erkennt, dass die
   Funktion fertig ist (Abnahmekriterien), einschließlich der Randfälle: leere Eingabe,
   falsche Eingabe, Verhalten für bestehende Aufrufe und Dateien. Gibt es eine
   Spezifikation im Projekt, gilt sie; ergänze nur, was fehlt.
3. **Plan.** Nenne die Dateien, die du änderst oder anlegst, und was jeweils geschieht.
   Neue feste Werte kommen in die Konfigurationsdatei des Projekts.
4. **Tests.** Schreibe zu jedem Abnahmekriterium mindestens einen Test in die Testdateien
   des Projekts.
5. **Code.** Setze den Plan um. Was vorher ging, muss weiter gehen.
6. **Prüfen.** Führe die Tests und, falls vorhanden, den Prüfbefehl des Projekts aus.
   Behebe Fehler, bis alles besteht.
7. **Dokumentation.** Trage das Neue in die README ein (Befehle, Optionen, Beispiele), bei
   Änderungen am Aufbau auch in die Dokumentation unter `docs`. Hat das Projekt eine
   `CHANGELOG.md`, ergänze einen Eintrag.
8. **Bericht.** Kurz: was geändert wurde, in welchen Dateien, was offen bleibt.

# Custom ILL module for Koha and Libris (For Swedish Libraries only)

## Installation:

1.  Ladda ned senaste releasen här: https://github.com/JSahlberg/koha-plugin-bm_librisill/releases
2.  Gå till **Koha-administration**
3.  Gå till **Hantera plugins**
4.  Klicka på **Ladda upp plugin**
5.  Välj KPZ-filen för pluginen och klicka på **Ladda upp**.

## Konfigurering:

### Hämta bibliotekets API-nycklar från Libris:

1. Logga in på ditt biblioteks konto på sidan: https://iller.libris.kb.se/librisfjarrlan/lf.php
2. Gå till **Inställningar**
3. Scrolla till längst ned på sidan så hittar du en kod i väldigt liten storlek
4. Kopiera koden
5. Gå till konfigureringssidan för pluginet genom att gå till **Koha-administration** -> **Hantera plugins**
6. Klicka på pluginets **Åtgärder**
7. Välj **Konfigurera**
8. I fältet för API-nycklar, skriv in bibliotekets sigel (t.ex. Tida) fäljt av ett mellanslag och sedan ett kolon och mellanslag igen. Klistra sedan in API-nyckeln från Libris. Det kan t.ex. se ut så här->  

   Tida : 872187218763213213876  

9. Om ni är fler bibliotek i eran Koha så fortsätt klistra in sigel och API-nycklar på var sin ny rad.


### Placeringar och status:

1.  Välj **Exemplartyp**, **Lokala placering**, **Avdelning** och **Status** som ni använder för att markera ett fjärrlån i erat system.
2.  Klicka på **Spara**


### Funktioner:

## Fjärrlåneförfrågningar

Här visas de aktuella fjärrlån man har importerat och skapat reserverationer på som ännu inte anlänt.

## Utlånade fjärrlån:

Här är de fjärrlån som är utlånade till låntagare.

## Importera fjärrlån (Libris)

Här visas de senaste fjärrlånen som gjorts på Libris Fjärrlån.
För att importera lånet in i Koha så klickar på man på **Behandla**.
En ny sida visas med informationen om fjärrlånet.
Klicka på **Importera och reservera** för att automatiskt importera in posten från Libris och reservera på låntagaren.

## Nya inkommande fjärrlån (Libris)

Här visas de obehandlade förfrågningarna som kommer från andra bibliotek som vill låna.
Tryck på **Behandla** för att öppna förfrågan.
Välj åtgärd och skriv in ev meddelande och om den kan ev reserveras om utlånad.
Klicka sedan på **Skicka** för att registrera på Libris fjärrlån.

## Arkiverade inkommande fjärrlån (Libris)

Här visas de förfrågningarna som har blivit behandlade.

## Sök borttagna fjärrlån

Här kan man söka på de fjärrlån man har haft registrerade och tagit bort från katalogen.


## Kontakt

Skapat av Johan Sahlberg 2025  
johan.sahlberg@tidaholm.se

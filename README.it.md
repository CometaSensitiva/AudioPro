# AudioPro

[English](README.md) · **Italiano**

Un’app macOS per le registrazioni delle lezioni: unisci e comprimi audio o video, trascrivi sul Mac e riascolta con il testo sincronizzato e cliccabile.

**[Scarica AudioPro](https://github.com/CometaSensitiva/AudioPro/releases/latest)**

![AudioPro: registrazioni pronte per l’esportazione](docs/screenshots/audio-merge-preview.png)

## Installazione

Richiede **macOS 26 o successivo**, su **Apple Silicon o Intel**.

Scarica `AudioPro-<version>-macOS.zip`, decomprimilo e sposta `AudioPro.app` in Applicazioni. Questa versione **non è notarizzata**: dopo il primo tentativo di apertura, vai in **Impostazioni di Sistema → Privacy e sicurezza → Apri comunque**, poi conferma **Apri**. [Guida d’installazione con screenshot](docs/install.it.md).

Whisper Large v3 viene scaricato separatamente da **Trascrizione** al primo uso; non è incluso nell’archivio dell’app. Il download richiede una connessione internet e diversi GB di spazio; poi la trascrizione avviene in locale.

## Come usarla

1. **Esportazione:** aggiungi le registrazioni, scegli audio o video compresso nelle impostazioni, poi premi **Esporta…**.
2. **Trascrizione:** scegli una registrazione, scarica il modello se richiesto, poi salva SRT, TXT o entrambi.
3. **Riproduzione:** apri la registrazione e il suo SRT. Clicca un segmento per raggiungerlo, cerca nel testo o cambia la velocità.

![AudioPro: riproduzione con la trascrizione sincronizzata](docs/screenshots/player-transcript.png)

Il lavoro continua quando cambi sezione. I file di destinazione esistenti restano intatti fino al completamento.

## Per sviluppatori

Clona il repository e apri `AudioPro.xcodeproj` in **Xcode 26 o successivo**, usando lo schema condiviso **AudioPro**. WhisperKit è fissato alla versione `1.0.0`; Xcode lo risolve alla prima build. Gli helper FFmpeg sono inclusi.

```sh
git clone https://github.com/CometaSensitiva/AudioPro.git
cd AudioPro
xcodebuild test -project AudioPro.xcodeproj -scheme AudioPro \
  -destination 'platform=macOS' INCLUDE_LOCAL_WHISPER_MODEL=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
./scripts/build-release.sh
```

Lo script crea uno ZIP universale e `SHA256SUMS.txt` in `dist/`. Un tag `v*` pubblicato avvia i test, genera l’archivio e pubblica una GitHub Release; l’avvio manuale del workflow genera solo gli artefatti.

[Dettagli di sviluppo e release](docs/development.md) (in inglese) · [Architettura](docs/architecture.md) · [Changelog](CHANGELOG.md) · [Licenza MIT](LICENSE). Gli strumenti di terze parti mantengono le proprie licenze.

# Coffeine

Coffeine je aplikace pro horní lištu macOS. Aplikace řídí, jestli se Mac může uspat. V režimu „Zakázat uspání“ se Mac neuspí ani po zaklopení víka.

## Funkce

- **Zakázat / Povolit uspání** (⌘S): zablokuje každé uspání systému, i po zaklopení víka.
- **Nechat svítit displej**: displej nezhasne při nečinnosti.
- **Povolit uspání při baterii ≤ 15 %**: pojistka. Pokud Mac běží na baterii a ta klesne na 15 %, Coffeine vrátí normální uspávání. Ve výchozím stavu je pojistka zapnutá.
- **Spouštět při přihlášení**: Coffeine se spustí automaticky po přihlášení.
- **Odebrat oprávnění pro pmset**: smaže pravidlo sudo, které aplikace vytvořila.
- **Ukončit**: při ukončení Coffeine vrátí normální uspávání.

Ikona v liště ukazuje stav. Plný šálek znamená, že se Mac neuspí. Prázdný šálek znamená normální uspávání.

## Požadavky

- macOS 13 nebo novější (Apple Silicon i Intel).
- Xcode 26 nebo novější. Build potřebuje `swiftc` a `actool`.
- Účet správce. Heslo je potřeba jednou, při prvním zakázání uspání.

## Sestavení a instalace

```sh
./build.sh            # sestaví build/Coffeine.app
./build.sh --install  # sestaví aplikaci, zkopíruje ji do /Applications a spustí ji
```

Pokud `actool` hlásí chybu „A required plugin failed to load“, spusťte `xcodebuild -runFirstLaunch`.

## Jak to funguje

Běžné nástroje (`caffeinate`, IOPM assertion) blokují jen uspání při nečinnosti. Uspání po zaklopení víka neblokují. Coffeine proto používá `pmset -a disablesleep 1`.

`pmset` potřebuje práva roota. Při prvním zakázání uspání Coffeine požádá o heslo správce. Potom vytvoří soubor `/etc/sudoers.d/coffeine`. Tento soubor dovolí aktuálnímu uživateli spustit bez hesla jen tyto dva příkazy:

```
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

Coffeine navíc vytvoří IOPM assertion proti uspání při nečinnosti. Pokud je zapnutá volba „Nechat svítit displej“, vytvoří také assertion pro displej.

Coffeine si pamatuje poslední stav a po restartu ho obnoví.

## Ověření stavu

```sh
pmset -g | grep SleepDisabled   # „SleepDisabled 1“ znamená, že uspání je zakázané
```

## Upozornění

- Pokud Coffeine spadne nebo ho někdo násilně ukončí, Mac zůstane ve stavu „neuspávat“. Spusťte Coffeine znovu, nebo použijte příkaz `sudo pmset -a disablesleep 0`.
- Zaklopený Mac, který se neuspí, se v tašce může přehřát.

## Odinstalace

1. V menu Coffeine vyberte „Odebrat oprávnění pro pmset…“.
2. Ukončete Coffeine.
3. Smažte `/Applications/Coffeine.app`.

## Struktura projektu

| Soubor | Účel |
|---|---|
| `Sources/main.swift` | Celá aplikace (AppKit, IOKit, ServiceManagement) |
| `Info.plist` | Metadata aplikace, `LSUIElement` (bez ikony v Docku) |
| `CoffeeeCup.icon` | Ikona aplikace z Icon Composeru |
| `build.sh` | Skript pro sestavení a instalaci |

# Authentik Stack

Docker-Compose-Stack für Authentik mit PostgreSQL, Traefik-Anbindung und einem eingeschränkten Docker-Socket-Proxy für die automatische Verwaltung von Outposts.

## Enthaltene Dienste

- `authentik-server`: Weboberfläche und API
- `authentik-worker`: Hintergrundaufgaben, Blueprints und Outpost-Verwaltung
- `authentik-database`: PostgreSQL 16
- `authentik-socket-proxy`: eingeschränkter Zugriff des Workers auf die Docker-API

Der Server hängt sowohl im internen `authentik`-Netz als auch im vorhandenen externen Traefik-Netz. Datenbank und Socket-Proxy sind ausschließlich über interne Netze erreichbar. Der Docker-Socket wird nicht direkt in den Authentik-Worker eingebunden.

## Voraussetzungen

- Linux-Server mit Docker Engine
- Docker Compose v2 (`docker compose`)
- OpenSSL
- ein bereits vorhandenes externes Docker-Netzwerk für Traefik, standardmäßig `proxy`
- Traefik mit aktiviertem Docker- und File-Provider
- mindestens 2 CPU-Kerne und 2 GB RAM

## Erstinstallation

Repository klonen, in das Verzeichnis wechseln und den Installer starten:

```bash
git clone https://github.com/happylippo/authentik-stack.git
cd authentik-stack
chmod +x first_install.sh
./first_install.sh
```

Das Skript fragt Domain, Authentik-Hostname, Version, Datenbanknamen, Benutzer, Traefik-Netzwerk, Certificate-Resolver, Trusted-Proxy-Adressen und die Server-IP im Proxy-Netz ab. Es erzeugt automatisch:

- ein zufälliges PostgreSQL-Passwort,
- einen zufälligen Authentik-Secret-Key,
- die nicht versionierte `.env`,
- die benötigten Datenverzeichnisse.

Eine vorhandene `.env` wird nur nach Rückfrage ersetzt und vorher mit UTC-Zeitstempel gesichert. Das Skript prüft außerdem das externe Traefik-Netzwerk und führt `docker compose config --quiet` aus.

Danach den Stack starten:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

Die Ersteinrichtung muss mit abschließendem Schrägstrich aufgerufen werden:

```text
https://authentik.example.com/if/flow/initial-setup/
```

## `.env` manuell erstellen

Alternativ kann die Beispieldatei kopiert und vollständig bearbeitet werden:

```bash
cp .env.example .env
chmod 600 .env
```

Mindestens `ABSOLUTE_PATH`, `PG_PASS`, `AUTHENTIK_SECRET_KEY`, Domain, Authentik-Hostname, Trusted Proxies sowie die Adressen im externen Traefik-Netz müssen stimmen. Die statischen Container-Adressen müssen innerhalb der jeweils konfigurierten Subnetze liegen und dürfen nicht bereits vergeben sein.

`AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` darf ausschließlich die tatsächlichen Adressen beziehungsweise CIDRs des Reverse-Proxys enthalten. Verwende nicht pauschal `0.0.0.0/0` oder `::/0`.

## Traefik-Middleware verwenden

[`config/html.middleware.authentik.yml`](config/html.middleware.authentik.yml) ist eine **Vorlage zum Kopieren in den Traefik-Stack**. Sie gehört nicht in Authentiks Datenverzeichnis.

Beispiel, wenn Traefiks File-Provider `data/traefik/dynamic/` überwacht:

```bash
cp config/html.middleware.authentik.yml /pfad/zum/traefik-stack/data/traefik/dynamic/html.middleware.authentik.yml
```

Traefik und `authentik-server` müssen dasselbe externe Docker-Netzwerk verwenden. Danach kann ein Router mit der Middleware geschützt werden:

```yaml
labels:
  traefik.http.routers.meine-app.middlewares: authentik@file
```

Bei einer Single-Application-Forward-Auth muss zusätzlich ein höher priorisierter Router mit der Regel `PathPrefix(\`/outpost.goauthentik.io/\`)` auf Authentik zeigen. Authentik kann die erforderlichen Router bei korrekt konfiguriertem eingebettetem Outpost über Docker-Labels verwalten. Wird das manuell erledigt, darf dieser Pfad selbst nicht wieder durch die Authentik-Middleware geschützt werden.

Die Vorlage nutzt intern:

```text
http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
```

Der Name ist im gemeinsamen Docker-Netz auflösbar; der Umweg über die öffentliche URL wird dadurch vermieden.

## Socket-Proxy

Der Worker erreicht die Docker-API über:

```text
tcp://authentik-socket-proxy:2375
```

Der versionierte Blueprint `blueprints/socket-proxy.yaml` legt dafür in Authentik die Docker-Service-Verbindung `Local Docker connection` mit derselben internen Adresse an.

Der Port wird nicht auf dem Host veröffentlicht. Der Proxy erlaubt die für Outposts benötigten Container- und Image-Abfragen sowie Start-/Stop-Aktionen. Schreibender Docker-API-Zugriff bleibt grundsätzlich sicherheitsrelevant. Wenn keine automatische Outpost-Verwaltung benötigt wird, können Socket-Proxy, `DOCKER_HOST`, das `authentik-socket`-Netz und die entsprechende `depends_on`-Abhängigkeit entfernt werden; Outposts müssen dann manuell verwaltet werden.

## Betrieb

Status und Logs anzeigen:

```bash
docker compose ps
docker compose logs -f authentik-server authentik-worker
```

Aktualisieren innerhalb des gewählten Release-Zweigs:

```bash
docker compose pull
docker compose up -d
```

Vor Versionswechseln sollte mindestens die PostgreSQL-Datenbank gesichert werden. Zusätzlich sind `data/`, `certs/`, `custom-templates/`, `blueprints/` und die `.env` relevant. Die `.env` enthält Geheimnisse und darf nicht ins Repository aufgenommen werden.

## Fehlerbehebung

Konfiguration prüfen:

```bash
docker compose config --quiet
```

Wenn Traefik `authentik-server` nicht erreicht, kontrolliere:

```bash
docker network inspect proxy
docker inspect authentik-server
```

Wenn Outposts nicht automatisch erstellt werden, prüfe Worker und Socket-Proxy:

```bash
docker compose logs authentik-worker authentik-socket-proxy
```

Bei `Not Found` während der Ersteinrichtung zuerst sicherstellen, dass die URL exakt mit `/if/flow/initial-setup/` endet.

## Wichtige Sicherheitshinweise

- `.env` mit Modus `600` schützen und nie committen.
- Den Port `2375` des Socket-Proxys niemals veröffentlichen.
- PostgreSQL nicht an ein öffentliches oder gemeinsames Proxy-Netz hängen.
- Vor Updates Datenbank-Backups erstellen und Restore regelmäßig testen.
- Authentik- und PostgreSQL-Versionen bewusst aktualisieren; keine unkontrollierten `latest`-Tags für diese Dienste verwenden.

## Offizielle Dokumentation

- [Authentik mit Docker Compose installieren](https://docs.goauthentik.io/install-config/install/docker-compose/)
- [Traefik Forward Auth](https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_traefik/)
- [Backup und Restore](https://docs.goauthentik.io/sys-mgmt/ops/backup-restore/)

#!/usr/bin/env python3
"""Lê os feeds RSS/Atom de scripts/feeds.json e grava manchetes das últimas 36 h.

Roda no GitHub Actions (rede livre). A redação lê o resultado do branch `feeds`
para saber o que cada veículo publicou, sem depender do buscador.

Uso: python3 scripts/coletar_feeds.py SAIDA.json
"""
import html
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
JANELA = timedelta(hours=36)
POR_FEED = 60
UA = "Mozilla/5.0 (compatible; NoticiasReaisBot/1.0; +https://github.com/hfneto/noticiasreais)"
ATOM = "{http://www.w3.org/2005/Atom}"


def limpar(t):
    t = html.unescape(re.sub(r"<[^>]+>", " ", t or ""))
    return re.sub(r"\s+", " ", t).strip()


def data(t):
    if not t:
        return None
    t = t.strip()
    try:
        d = parsedate_to_datetime(t)
    except (TypeError, ValueError):
        try:
            d = datetime.fromisoformat(t.replace("Z", "+00:00"))
        except ValueError:
            return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def texto(el, *tags):
    for tag in tags:
        achado = el.find(tag)
        if achado is not None and (achado.text or "").strip():
            return achado.text
    return None


def ler(feed):
    req = urllib.request.Request(feed["url"], headers={"User-Agent": UA, "Accept": "application/rss+xml, application/xml, text/xml, */*"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            corpo = r.read()
        raiz = ET.fromstring(corpo)
    except Exception as e:  # noqa: BLE001
        return {**feed, "status": f"erro: {type(e).__name__}: {str(e)[:120]}", "itens": []}

    itens = []
    for it in raiz.iter("item"):  # RSS 2.0 / 0.91
        itens.append((texto(it, "title"), texto(it, "link", "guid"),
                      texto(it, "pubDate", "{http://purl.org/dc/elements/1.1/}date")))
    for it in raiz.iter(f"{ATOM}entry"):  # Atom
        link = next((l.get("href") for l in it.findall(f"{ATOM}link") if l.get("rel", "alternate") == "alternate"), None)
        itens.append((texto(it, f"{ATOM}title"), link, texto(it, f"{ATOM}published", f"{ATOM}updated")))

    agora = datetime.now(timezone.utc)
    saida = []
    for titulo, link, quando in itens[:POR_FEED]:
        titulo, link = limpar(titulo), (link or "").strip()
        if not titulo or not link.startswith("http"):
            continue
        d = data(quando)
        if d and agora - d > JANELA:
            continue
        saida.append({"fonte": feed["fonte"], "titulo": titulo, "url": link.replace("http://", "https://", 1),
                      "publicado_em": d.isoformat(timespec="minutes") if d else None})
    status = "ok" if saida else ("vazio" if itens else "sem itens reconhecidos")
    return {**feed, "status": status, "itens": saida}


def main():
    destino = Path(sys.argv[1] if len(sys.argv) > 1 else "manchetes.json")
    feeds = json.loads((RAIZ / "scripts" / "feeds.json").read_text(encoding="utf-8"))["feeds"]
    with ThreadPoolExecutor(max_workers=16) as ex:
        resultados = list(ex.map(ler, feeds))
    vistos, itens = set(), []
    for r in resultados:
        for i in r["itens"]:
            if i["url"] not in vistos:
                vistos.add(i["url"])
                itens.append(i)
    itens.sort(key=lambda i: i["publicado_em"] or "", reverse=True)
    doc = {
        "coletado_em": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "janela_horas": int(JANELA.total_seconds() // 3600),
        "feeds": [{"fonte": r["fonte"], "url": r["url"], "status": r["status"], "itens": len(r["itens"])} for r in resultados],
        "itens": itens,
    }
    destino.write_text(json.dumps(doc, ensure_ascii=False, indent=0) + "\n", encoding="utf-8")
    ok = sum(1 for r in resultados if r["status"] == "ok")
    print(f"{ok}/{len(resultados)} feeds ok, {len(itens)} manchetes")
    for r in resultados:
        if r["status"] != "ok":
            print(f"  {r['fonte']}: {r['status']} ({r['url']})")


if __name__ == "__main__":
    main()

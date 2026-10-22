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
RESUMO_MAX = 420  # caracteres do primeiro parágrafo guardados por manchete
UA = "Mozilla/5.0 (compatible; NoticiasReaisBot/1.0; +https://github.com/hfneto/noticiasreais)"
ATOM = "{http://www.w3.org/2005/Atom}"


def limpar(t):
    t = html.unescape(re.sub(r"<[^>]+>", " ", t or ""))
    return re.sub(r"\s+", " ", t).strip()


def resumo(t):
    """Primeiro parágrafo da matéria, sem HTML e sem 'leia mais'; vazio se for só o título repetido."""
    t = limpar(html.unescape(t or ""))
    t = re.sub(r"\b(Leia mais|Continue lendo|Saiba mais|The post .* appeared first on .*|O post .* apareceu primeiro em .*)\b.*$", "", t, flags=re.I).strip()
    if len(t) > RESUMO_MAX:
        corte = t[:RESUMO_MAX].rsplit(" ", 1)[0]
        t = corte + "…"
    return t


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


def _tag(bloco, *nomes):
    for n in nomes:
        m = re.search(rf"<{n}\b[^>]*>(.*?)</{n}>", bloco, re.S | re.I)
        if m:
            return re.sub(r"^\s*<!\[CDATA\[(.*)\]\]>\s*$", r"\1", m.group(1), flags=re.S)
    return None


def extrair_tolerante(corpo):
    """Para feeds com XML malformado: lê item a item com expressões regulares."""
    txt = corpo.decode("utf-8", errors="replace")
    itens = []
    for bloco in re.findall(r"<item\b.*?</item>", txt, re.S | re.I):
        itens.append((_tag(bloco, "title"), _tag(bloco, "link", "guid"), _tag(bloco, "pubDate", "dc:date"),
                      _tag(bloco, "description", "content:encoded")))
    for bloco in re.findall(r"<entry\b.*?</entry>", txt, re.S | re.I):
        m = re.search(r'<link\b[^>]*href="([^"]+)"', bloco)
        itens.append((_tag(bloco, "title"), m.group(1) if m else None, _tag(bloco, "published", "updated"),
                      _tag(bloco, "summary", "content")))
    return itens


def extrair(corpo):
    try:
        raiz = ET.fromstring(corpo)
    except ET.ParseError:
        return extrair_tolerante(corpo)
    itens = []
    for it in raiz.iter("item"):  # RSS 2.0 / 0.91
        itens.append((texto(it, "title"), texto(it, "link", "guid"),
                      texto(it, "pubDate", "{http://purl.org/dc/elements/1.1/}date"),
                      texto(it, "description", "{http://purl.org/rss/1.0/modules/content/}encoded")))
    for it in raiz.iter(f"{ATOM}entry"):  # Atom
        link = next((l.get("href") for l in it.findall(f"{ATOM}link") if l.get("rel", "alternate") == "alternate"), None)
        itens.append((texto(it, f"{ATOM}title"), link, texto(it, f"{ATOM}published", f"{ATOM}updated"),
                      texto(it, f"{ATOM}summary", f"{ATOM}content")))
    return itens


def baixar(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/rss+xml, application/xml, text/xml, */*"})
    with urllib.request.urlopen(req, timeout=25) as r:
        return r.read()


def ler(feed):
    """Tenta a url e, se falhar ou vier vazia, cada uma das `alternativas`; fica com a primeira que der itens."""
    tentativas = [feed["url"], *feed.get("alternativas", [])]
    ultimo = None
    for url in tentativas:
        r = ler_url({"fonte": feed["fonte"], "url": url})
        if r["status"] == "ok":
            return r
        ultimo = ultimo if ultimo and ultimo["status"].startswith("vazio") else r
    return ultimo


def ler_url(feed):
    try:
        itens = extrair(baixar(feed["url"]))
    except Exception as e:  # noqa: BLE001
        return {**feed, "status": f"erro: {type(e).__name__}: {str(e)[:120]}", "itens": []}

    agora = datetime.now(timezone.utc)
    saida = []
    for titulo, link, quando, descricao in itens[:POR_FEED]:
        titulo, link = limpar(titulo), (link or "").strip()
        if not titulo or not link.startswith("http"):
            continue
        d = data(quando)
        if d and agora - d > JANELA:
            continue
        r = resumo(descricao)
        if r.lower().rstrip(".…") == titulo.lower().rstrip("."):
            r = ""
        saida.append({"fonte": feed["fonte"], "titulo": titulo, "url": link.replace("http://", "https://", 1),
                      "publicado_em": d.isoformat(timespec="minutes") if d else None, "resumo": r})
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

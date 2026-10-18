#!/usr/bin/env python3
"""Valida edições e buscas e reconstrói data/index.json.

Uso:
  python3 scripts/validar.py                 # valida tudo e reescreve o índice
  python3 scripts/validar.py ARQUIVO.json    # valida só esse arquivo (e reescreve o índice)

Sai com código 1 se encontrar erro. Avisos não bloqueiam.
"""
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DADOS = RAIZ / "data"
VIESES = {"esquerda", "centro_esquerda", "centro", "centro_direita", "direita"}
ROTULOS = {"Falso", "Sem evidência", "Falta contexto", "Exagerado", "Distorcido", "Contraditório", "Em apuração", "Verdadeiro"}
ENQUADRAMENTOS = {"pro_governo", "neutro", "oposicao", None}
TIPOS_MATERIA = {"noticia", "analise", "opiniao", "checagem", "fonte_primaria"}
ESCOPOS = {"brasil", "mundo"}
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def carregar_fontes():
    dados = json.loads((DADOS / "fontes.json").read_text(encoding="utf-8"))
    return {f["id"]: f for f in dados["fontes"]}


def texto(v, minimo=1):
    return isinstance(v, str) and len(v.strip()) >= minimo


def validar_historia(h, fontes, onde, erros, avisos):
    p = f"{onde} › {h.get('id', '?')}"
    if not (isinstance(h.get("id"), str) and SLUG.match(h["id"])):
        erros.append(f"{p}: id deve ser slug minúsculo com hífens")
    for campo in ("editoria", "titulo", "lide"):
        if not texto(h.get(campo)):
            erros.append(f"{p}: campo '{campo}' vazio")
    if h.get("escopo") not in ESCOPOS:
        erros.append(f"{p}: escopo deve ser brasil ou mundo")

    fatos = h.get("fatos") or []
    if not fatos:
        erros.append(f"{p}: precisa de ao menos 1 fato")
    for i, f in enumerate(fatos):
        if not texto(f.get("texto")):
            erros.append(f"{p}: fato {i} sem texto")
        if not texto(f.get("base")):
            erros.append(f"{p}: fato {i} sem 'base' (ex.: '3 fontes independentes', 'documento oficial')")

    for i, x in enumerate(h.get("inferencias") or []):
        if not (texto(x.get("texto")) and texto(x.get("quem"))):
            erros.append(f"{p}: inferência {i} precisa de texto e quem")

    for i, d in enumerate(h.get("em_disputa") or []):
        if not texto(d.get("alegacao")) or not texto(d.get("explicacao")):
            erros.append(f"{p}: disputa {i} precisa de alegacao e explicacao")
        if d.get("rotulo") not in ROTULOS:
            erros.append(f"{p}: disputa {i} com rótulo inválido '{d.get('rotulo')}'. Use: {sorted(ROTULOS)}")
        for c in d.get("checagem") or []:
            if not str(c.get("url", "")).startswith("https://"):
                erros.append(f"{p}: disputa {i} com link de checagem inválido")

    enq = h.get("enquadramentos")
    if enq is not None and not (texto(enq.get("governo")) and texto(enq.get("oposicao"))):
        erros.append(f"{p}: enquadramentos precisa de governo e oposicao, ou null")

    materias = h.get("materias") or []
    if len(materias) < 3:
        erros.append(f"{p}: precisa de ao menos 3 matérias (tem {len(materias)})")
    urls = set()
    lados = set()
    for i, m in enumerate(materias):
        q = f"{p}: matéria {i}"
        url = m.get("url", "")
        if not (isinstance(url, str) and url.startswith("https://")):
            erros.append(f"{q}: url precisa começar com https://")
        if url in urls:
            erros.append(f"{q}: url repetida")
        urls.add(url)
        if not texto(m.get("titulo")):
            erros.append(f"{q}: sem titulo")
        if not texto(m.get("angulo")):
            avisos.append(f"{q}: sem 'angulo'")
        if m.get("tipo", "noticia") not in TIPOS_MATERIA:
            erros.append(f"{q}: tipo inválido '{m.get('tipo')}'")
        if m.get("enquadramento") not in ENQUADRAMENTOS:
            erros.append(f"{q}: enquadramento inválido '{m.get('enquadramento')}'")
        fid = m.get("fonte")
        f = fontes.get(fid) if fid else None
        if fid and not f:
            erros.append(f"{q}: fonte '{fid}' não existe em fontes.json (use null e preencha veiculo + vies_materia)")
        if f is None and not texto(m.get("veiculo")):
            erros.append(f"{q}: sem fonte cadastrada precisa do nome em 'veiculo'")
        vies = f["vies"] if f and f["vies"] in VIESES else m.get("vies_materia")
        if vies not in VIESES:
            erros.append(f"{q}: veículo sem viés cadastrado precisa de vies_materia válido")
        else:
            lados.add("E" if "esquerda" in vies else "D" if "direita" in vies else "C")
    if materias and len(lados) < 2 and not texto(h.get("ponto_cego")):
        avisos.append(f"{p}: só um lado do espectro e nenhum ponto_cego explicado")


def validar_arquivo(caminho, fontes):
    erros, avisos = [], []
    try:
        doc = json.loads(Path(caminho).read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return [f"{caminho}: JSON inválido ({e})"], []
    nome = Path(caminho).name
    tipo = doc.get("tipo")
    if tipo == "edicao":
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(doc.get("data", ""))):
            erros.append(f"{nome}: data deve ser AAAA-MM-DD")
        if nome != f"{doc.get('data')}.json":
            erros.append(f"{nome}: nome do arquivo deve ser {doc.get('data')}.json")
    elif tipo == "busca":
        if not (isinstance(doc.get("slug"), str) and SLUG.match(doc["slug"])):
            erros.append(f"{nome}: slug inválido")
        if not texto(doc.get("consulta")):
            erros.append(f"{nome}: consulta vazia")
    else:
        erros.append(f"{nome}: tipo deve ser 'edicao' ou 'busca'")
    if not texto(doc.get("gerado_em")):
        erros.append(f"{nome}: gerado_em vazio")
    historias = doc.get("historias") or []
    if not historias:
        erros.append(f"{nome}: nenhuma história")
    ids = [h.get("id") for h in historias]
    if len(ids) != len(set(ids)):
        erros.append(f"{nome}: ids de história repetidos")
    for h in historias:
        validar_historia(h, fontes, nome, erros, avisos)
    return erros, avisos


def reconstruir_indice():
    edicoes = []
    for arq in sorted((DADOS / "edicoes").glob("*.json"), reverse=True):
        d = json.loads(arq.read_text(encoding="utf-8"))
        edicoes.append({
            "data": d["data"],
            "arquivo": f"data/edicoes/{arq.name}",
            "historias": len(d.get("historias", [])),
            "gerado_em": d.get("gerado_em"),
            "manchete": (d.get("historias") or [{}])[0].get("titulo", ""),
        })
    buscas = []
    for arq in (DADOS / "buscas").glob("*.json"):
        d = json.loads(arq.read_text(encoding="utf-8"))
        buscas.append({
            "slug": d["slug"],
            "consulta": d["consulta"],
            "arquivo": f"data/buscas/{arq.name}",
            "historias": len(d.get("historias", [])),
            "gerado_em": d.get("gerado_em"),
            "issue": d.get("issue"),
        })
    buscas.sort(key=lambda b: b.get("gerado_em") or "", reverse=True)
    indice = {
        "atualizado_em": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "edicoes": edicoes,
        "buscas": buscas,
    }
    (DADOS / "index.json").write_text(json.dumps(indice, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return indice


def main():
    fontes = carregar_fontes()
    (DADOS / "edicoes").mkdir(parents=True, exist_ok=True)
    (DADOS / "buscas").mkdir(parents=True, exist_ok=True)
    alvos = sys.argv[1:] or [*map(str, (DADOS / "edicoes").glob("*.json")), *map(str, (DADOS / "buscas").glob("*.json"))]
    total_erros = 0
    for alvo in alvos:
        erros, avisos = validar_arquivo(alvo, fontes)
        for a in avisos:
            print(f"aviso: {a}")
        for e in erros:
            print(f"ERRO: {e}")
        total_erros += len(erros)
    if total_erros:
        print(f"\n{total_erros} erro(s). Corrija antes de publicar.")
        sys.exit(1)
    indice = reconstruir_indice()
    print(f"OK. Índice: {len(indice['edicoes'])} edição(ões), {len(indice['buscas'])} busca(s).")


if __name__ == "__main__":
    main()

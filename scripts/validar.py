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
DOC_PRIMARIO = re.compile(r"diário oficial|decisão|acórdão|nota oficial|documento|lei\b|decreto|portaria|relatório|boletim|ata\b|vídeo|dado oficial|ibge|tse|stf|senado|câmara|ministério|secretaria|pnuma|onu|oms", re.I)
EDITORIAS_POLITICA = {"política", "politica", "eleições", "eleicoes", "justiça", "justica"}


def _norm(t):
    import unicodedata
    t = unicodedata.normalize("NFKD", t or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", t).strip()


def grupo(f):
    """Chave do grupo econômico: fontes com o mesmo controlador não são independentes entre si."""
    return f.get("grupo") or _norm(re.sub(r"\(.*?\)", "", f.get("dono") or f["id"]))


def resolver_fonte(nome, fontes, por_nome):
    n = _norm(nome)
    if n in fontes:
        return fontes[n]
    if n in por_nome:
        return por_nome[n]
    for k, f in por_nome.items():
        if n and (n in k or k in n):
            return f
    return None


def checar_independencia(h, fontes, p, erros, avisos):
    """Regra do CLAUDE.md: fato precisa de 2+ fontes de grupos diferentes ou documento primário."""
    por_nome = {_norm(f["nome"]): f for f in fontes.values()}
    grupos_materias = set()
    for m in h.get("materias") or []:
        f = fontes.get(m.get("fonte") or "")
        grupos_materias.add(grupo(f) if f else _norm(m.get("veiculo") or "?"))
    for i, fato in enumerate(h.get("fatos") or []):
        base = fato.get("base") or ""
        m = re.match(r"\s*(\d+)\s+fontes?", base, re.I)
        if not m:
            continue  # base é documento/fonte nomeada; não dá para checar automaticamente
        n = int(m.group(1))
        if n < 2 and not DOC_PRIMARIO.search(base):
            erros.append(f"{p}: fato {i} com 1 fonte e sem documento primário: '{base}'")
        nomes = re.findall(r"\(([^)]*)\)", base)
        citadas = [x.strip() for x in re.split(r",|;| e ", nomes[0]) if x.strip()] if nomes else []
        resolvidas = [resolver_fonte(x.split("/")[0], fontes, por_nome) for x in citadas]
        resolvidas = [f for f in resolvidas if f]
        if len(resolvidas) >= 2 and len(resolvidas) == len(citadas):
            if len({grupo(f) for f in resolvidas}) < 2:
                erros.append(f"{p}: fato {i} cita só fontes do mesmo grupo ({', '.join(f['nome'] for f in resolvidas)}): '{base}'")
        if n > max(len(grupos_materias), 1) + 1:
            avisos.append(f"{p}: fato {i} diz {n} fontes, mas as matérias da história vêm de {len(grupos_materias)} grupo(s)")


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

    cont = h.get("continua")
    if cont is not None:
        if not (isinstance(cont, dict) and re.match(r"^\d{4}-\d{2}-\d{2}$", str(cont.get("data", ""))) and isinstance(cont.get("id"), str) and SLUG.match(cont["id"])):
            erros.append(f"{p}: continua precisa de data (AAAA-MM-DD) e id (slug)")
        else:
            arq = DADOS / "edicoes" / f"{cont['data']}.json"
            if arq.exists():
                ids = {x.get("id") for x in json.loads(arq.read_text(encoding="utf-8")).get("historias", [])}
                if cont["id"] not in ids:
                    erros.append(f"{p}: continua aponta para {cont['data']}/{cont['id']}, que não existe")
            else:
                avisos.append(f"{p}: continua aponta para edição {cont['data']}, não encontrada")
            if not texto(cont.get("titulo")):
                avisos.append(f"{p}: continua sem 'titulo' (o app mostra o título da história anterior)")
    checar_independencia(h, fontes, p, erros, avisos)

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
    from collections import Counter
    rep = Counter((m.get("fonte") or (m.get("veiculo") or "").lower()) for m in materias)
    for k, n in rep.items():
        if n > 2:
            avisos.append(f"{p}: veículo '{k}' aparece {n} vezes; prefira variar (a barra conta cada veículo uma vez)")


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
    if tipo == "edicao" and len(historias) >= 6:
        pol = sum(1 for h in historias if str(h.get("editoria", "")).strip().lower() in EDITORIAS_POLITICA)
        if pol / len(historias) > 0.7:
            avisos.append(f"{nome}: {pol} de {len(historias)} histórias são Política/Eleições/Justiça; o CLAUDE.md pede ao menos 3 de outras editorias")
        brasil = sum(1 for h in historias if h.get("escopo") == "brasil")
        if not 0.5 <= brasil / len(historias) <= 0.8:
            avisos.append(f"{nome}: {brasil} de {len(historias)} histórias são do Brasil; a meta é cerca de 2/3")
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

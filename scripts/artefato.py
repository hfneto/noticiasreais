"""Gera a versão de artefato (claude.ai) do app a partir de index.html.

Uso: python3 scripts/artefato.py <saida.html>

O artefato publica index.html adaptado + os JSONs de data/ como arquivos
anexos. Quem abre o artefato com o conector do GitHub ligado vê a edição
mais nova direto do repositório e pode pedir buscas sem sair da página.
"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

# Lê os dados ao vivo pelo conector do GitHub (capacidade `mcp` do artefato).
VIVO = r'''
const GH = "GitHub", DONO = "hfneto", REP = "noticiasreais";
const mcpP = (window.claude && window.claude.use) ? window.claude.use("mcp").catch(() => null) : Promise.resolve(null);
function textoDe(res){
  for (const b of res?.content || []) if (b.type === "resource" && typeof b.resource?.text === "string") return b.resource.text;
  for (const b of res?.content || []) if (b.type === "text" && /^\s*[{[]/.test(b.text)) return b.text;
  return null;
}
async function aoVivo(path){
  const m = await mcpP; if (!m) return null;
  try {
    const r = await m.callTool(GH, "get_file_contents", {owner:DONO, repo:REP, path}, {cache:{staleTime:600000, gcTime:3600000}});
    const t = textoDe(r); return t ? JSON.parse(t) : null;
  } catch { return null; }
}
async function atualizarAoVivo(){
  const vivo = await aoVivo("data/index.json");
  if (!vivo || !Array.isArray(vivo.edicoes)) return;
  if ((vivo.atualizado_em || "") <= (IDX?.atualizado_em || "")) return;
  cache["data/index.json"] = vivo; IDX = vivo;
  if (window.scrollY < 80) route(); else toast("Há uma edição mais nova. Volte ao topo para ver.");
}
'''

GETJSON_NOVO = '''async function getJSON(path){
  if (cache[path]) return cache[path];
  try {
    const r = await fetch(path, {cache:"no-cache"});
    if (r.ok) return cache[path] = await r.json();
  } catch {}
  const v = await aoVivo(path);
  if (v) return cache[path] = v;
  throw new Error(path + " indisponível");
}'''

PENDENTES_NOVO = '''async function pendentesGitHub(){
  const m = await mcpP; if (!m) return null;
  try {
    const r = await m.callTool(GH, "list_issues", {owner:DONO, repo:REP, state:"OPEN", perPage:50, fields:["number","title","created_at"]}, {cache:false});
    const p = typeof r.payload === "object" ? r.payload : JSON.parse(textoDe(r) || "{}");
    const feitas = new Set(IDX.buscas.map(b => b.issue).filter(Boolean));
    return (p.issues || []).filter(i => /^busca:/i.test(i.title) && !feitas.has(i.number));
  } catch { return null; }
}'''

ENVIO_NOVO = '''  document.getElementById("f").addEventListener("submit", async e => {
    e.preventDefault();
    const t = q.value.trim(); if (!t) return;
    const btn = e.target.querySelector("button"); btn.disabled = true;
    const m = await mcpP;
    const link = `https://github.com/${REPO}/issues/new?title=${encodeURIComponent("busca: " + t)}&body=${encodeURIComponent("Pedido feito pelo artefato.")}`;
    const alt = document.getElementById("alt");
    if (!m){ alt.innerHTML = `Sem o conector do GitHub nesta visualização. <a href="${link}" target="_blank" rel="noopener">Abrir o pedido no GitHub ↗</a>`; btn.disabled = false; return; }
    try {
      const r = await m.callTool(GH, "issue_write", {method:"create", owner:DONO, repo:REP, title:"busca: " + t, body:"Pedido feito pelo artefato do Notícias Reais."});
      q.value = ""; toast("Pedido registrado. Fica pronto na próxima checagem da manhã.");
      viewBuscas();
    } catch (err) {
      const c = err?.code;
      alt.innerHTML = c === "server_not_connected" || c === "needs_reauth" ? `Conecte o GitHub em claude.ai → Configurações → Conectores, ou <a href="${link}" target="_blank" rel="noopener">abra o pedido no GitHub ↗</a>.`
        : c === "not_in_manifest" || c === "approval_required" ? `O pedido precisa da sua autorização para usar o GitHub nesta página. Tente de novo e permita, ou <a href="${link}" target="_blank" rel="noopener">abra no GitHub ↗</a>.`
        : `Não deu para confirmar o pedido agora (${esc(c || "erro")}). Confira a fila antes de tentar de novo, ou <a href="${link}" target="_blank" rel="noopener">abra no GitHub ↗</a>.`;
      btn.disabled = false;
    }
  });'''


def troca(src, velho, novo, regex=False):
    if regex:
        novo_src, n = re.subn(velho, lambda _: novo, src, count=1, flags=re.S)
    else:
        n = src.count(velho)
        novo_src = src.replace(velho, novo, 1)
    if not n:
        raise SystemExit(f"trecho não encontrado em index.html: {velho[:60]!r}")
    return novo_src


def gerar():
    s = (RAIZ / "index.html").read_text(encoding="utf-8")
    # O publicador do artefato já envolve a página em <html><head><body>.
    for tag in ("<!doctype html>", '<html lang="pt-BR">', "<head>", "</head>", "<body>", "</body>", "</html>"):
        s = troca(s, tag, "")
    s = re.sub(r'<link rel="(manifest|icon|apple-touch-icon)"[^>]*>\n?', "", s)
    s = re.sub(r'<meta name="(apple-mobile-web-app-[a-z-]+|mobile-web-app-capable|theme-color)"[^>]*>\n?', "", s)
    s = troca(s, '\nif ("serviceWorker" in navigator', '\nif (false && "serviceWorker" in navigator')
    s = troca(s, '"use strict";', '"use strict";' + VIVO)
    s = troca(s, r"async function getJSON\(path\)\{.*?\n\}", GETJSON_NOVO, regex=True)
    s = troca(s, r"async function pendentesGitHub\(\)\{.*?\n\}", PENDENTES_NOVO, regex=True)
    s = troca(s, r'  document\.getElementById\("f"\)\.addEventListener\("submit", e => \{.*?\n  \}\);', ENVIO_NOVO, regex=True)
    s = troca(s, "<p>Abre o GitHub com o pedido pronto: toque em <b>Create</b>. A pesquisa completa, com todos os lados, fica pronta em até 1 hora.</p>",
              '<p>O pedido vai direto para a fila pelo seu conector do GitHub. A fila é processada de hora em hora entre 7h e 11h (Brasília).</p><p id="alt"></p>')
    s = troca(s, "  route();\n}", "  route();\n  atualizarAoVivo();\n}")
    s = troca(s, "entram numa fila processada a cada hora.", "entram numa fila processada de hora em hora entre 7h e 11h (Brasília).")
    s = re.sub(r'<meta (charset|name="viewport")[^>]*>\n?', "", s)
    return s.lstrip()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    Path(sys.argv[1]).write_text(gerar(), encoding="utf-8")

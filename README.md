# Caça ao Orc — AR

Jogo 3D em realidade aumentada que roda direto no navegador do celular (Three.js + WebXR).
Primeiro o cenário (árvores, pedras e tocos) é fixado ao seu redor; depois o orc entra e anda por ele. Você gira o corpo para procurá-lo (uma seta verde aponta a direção). Ele se esconde do lado oposto ao seu,
sai para espiar e joga machadinhas, flechas e pedras. Você revida com bombas.

**Jogar:** https://mapolanski2020.github.io/Orc_AR/

## Modos
| Modo | Onde funciona | Como é |
|---|---|---|
| **Jogar em AR** | Chrome no Android (ARCore) | Escaneia o chão, toque no anel laranja para colocar a arena. Ande para desviar. |
| **Usar a câmera** | Android e iPhone | Orc sobre a imagem da câmera; mira girando o celular. |
| **Floresta 3D** | Qualquer navegador | Cenário virtual; arraste para olhar, ◀ ▶ para esquivar. |

A câmera e o AR exigem HTTPS (o GitHub Pages já é).

## Regras
- Toque para lançar a bomba. Ela voa em arco: dá para passar por cima de pedras e tocos, mas não de árvores.
- Se a explosão acerta a cobertura, o orc fica protegido. Acerto em cheio causa dano dobrado.
- Acerto: 25 × onda · Orc derrubado: 100 × onda · Desvio por pouco: 5 × onda.
- 5 corações; cada orc derrubado devolve 1. A cada onda o orc fica mais rápido, certeiro e resistente.

## Tecnologia
Arquivo único `index.html`, sem build. Three.js r128 via CDN, WebXR `immersive-ar` com `hit-test` e `dom-overlay`,
`getUserMedia` + `deviceorientation` como alternativa, sons sintetizados com Web Audio.

// 把 mobile/assets/legal/*.md 渲染成可直接发布的静态页（docs/legal/*.html）。
// 用 App 里那份 markdown 作为唯一来源：App 内用 flutter_markdown_plus 渲染同一份文件，
// 这里用 Web 端已有的 marked 依赖生成网页，避免两处维护。
//
// 用法：node scripts/build-legal.mjs
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { marked } from 'marked'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const sourceDir = join(root, 'mobile/assets/legal')
const outputDir = join(root, 'docs/legal')

const docs = [
  { file: 'privacy', title: '探境 隐私政策' },
  { file: 'terms', title: '探境 用户协议' },
  { file: 'support', title: '探境 支持' },
]

const style = `
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 40px 20px 72px;
      background: #f8f8fd;
      color: #202038;
      font: 16px/1.85 -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Helvetica Neue", sans-serif;
    }
    main {
      max-width: 760px;
      margin: 0 auto;
      padding: 40px 36px 48px;
      background: #fff;
      border: 1px solid #ededf5;
      border-radius: 18px;
      box-shadow: 0 16px 45px rgba(70, 67, 123, .05);
    }
    h1 { margin: 0 0 8px; font-size: 26px; line-height: 1.4; }
    h2 { margin: 34px 0 10px; font-size: 18px; }
    h3 { margin: 24px 0 8px; font-size: 16px; }
    p, li { color: #4a4a63; }
    ul { padding-left: 22px; }
    li { margin: 4px 0; }
    a { color: #6658e8; }
    table { width: 100%; border-collapse: collapse; margin: 12px 0; font-size: 14.5px; }
    th, td { padding: 9px 12px; border: 1px solid #ededf5; text-align: left; }
    th { background: #f5f4ff; font-weight: 600; }
    hr { margin: 32px 0; border: 0; border-top: 1px solid #ededf5; }
    footer { max-width: 760px; margin: 20px auto 0; color: #7c7c96; font-size: 13px; text-align: center; }
    footer a { color: #7c7c96; }
    @media (max-width: 560px) {
      body { padding: 20px 12px 48px; }
      main { padding: 26px 20px 32px; border-radius: 14px; }
      h1 { font-size: 22px; }
    }
`

const nav = (current) => {
  const links = [
    ['index.html', '支持'],
    ['privacy.html', '隐私政策'],
    ['terms.html', '用户协议'],
  ]
  return `<p>${links
    .map(([href, label]) =>
      href === current ? `<strong>${label}</strong>` : `<a href="${href}">${label}</a>`,
    )
    .join(' · ')}</p>`
}

const page = ({ title, body, current }) => `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>${style}</style>
</head>
<body>
<main>
${nav(current)}
<hr>
${body}
</main>
<footer>探境 · Explore · <a href="https://github.com/zhoubo416/explorer">github.com/zhoubo416/explorer</a></footer>
</body>
</html>
`

await mkdir(outputDir, { recursive: true })

for (const doc of docs) {
  const markdown = await readFile(join(sourceDir, `${doc.file}.md`), 'utf8')
  const body = marked.parse(markdown, { mangle: false, headerIds: false })
  const html = page({ title: doc.title, body, current: `${doc.file}.html` })
  await writeFile(join(outputDir, `${doc.file}.html`), html)
  console.log(`已生成 docs/legal/${doc.file}.html`)
}

// 支持页同时充当入口页：App Store Connect 的支持 URL 直接用 index.html
const support = await readFile(join(sourceDir, 'support.md'), 'utf8')
const indexBody = marked.parse(support, { mangle: false, headerIds: false })
await writeFile(
  join(outputDir, 'index.html'),
  page({ title: '探境 支持', body: indexBody, current: 'index.html' }),
)
console.log('已生成 docs/legal/index.html')

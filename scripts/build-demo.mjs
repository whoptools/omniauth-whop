import { mkdir, copyFile, writeFile } from 'node:fs/promises';
import { gray, grayDark, orange, orangeDark, blue, blueDark, green, greenDark, red, redDark } from '@frosted-ui/colors';
const roles = (g, o, b, s, e, background) => ({
  background, text: g.gray12, muted: g.gray11, surface: g.gray3, border: g.gray6,
  control: g.gray9, link: b.blue11, focus: b.blue11, primary: o.orange9,
  'primary-hover': o.orange10, 'primary-text': '#000000', success: s.green11, danger: e.red11,
});
const declarations = values => Object.entries(values).map(([key,value]) => `--ui-${key}:${value};`).join('');
await mkdir('examples/public/fonts', {recursive:true});
await mkdir('examples/public/licenses', {recursive:true});
await copyFile('node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2','examples/public/fonts/inter-latin.woff2');
await copyFile('node_modules/@fontsource-variable/inter/LICENSE','examples/public/licenses/inter.txt');
await copyFile('node_modules/@frosted-ui/colors/LICENSE','examples/public/licenses/frosted-colors.txt');
await writeFile('examples/public/theme.css', `/* Generated from Whop Frosted UI. System theme only. */
@font-face{font-family:'Inter Variable';font-style:normal;font-weight:100 900;font-display:swap;src:url('/assets/fonts/inter-latin.woff2') format('woff2')}
:root{color-scheme:light;${declarations(roles(gray,orange,blue,green,red,'#ffffff'))}}
@media(prefers-color-scheme:dark){:root{color-scheme:dark;${declarations(roles(grayDark,orangeDark,blueDark,greenDark,redDark,grayDark.gray1))}}}
`);

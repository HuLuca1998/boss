import {build} from 'esbuild';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url)),outfile=path.resolve(process.argv[2]||path.join(root,'dist/ExplorationMCP.mjs'));
await fs.mkdir(path.dirname(outfile),{recursive:true});
const output=await build({entryPoints:[path.join(root,'server.mjs')],outfile,bundle:true,platform:'node',format:'esm',target:'node22',legalComments:'linked',metafile:true,banner:{js:"import {createRequire as __createRequire} from 'node:module';const require=__createRequire(import.meta.url);"}});
const packages=new Set();
for(const input of Object.keys(output.metafile.inputs)){const match=input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/);if(match)packages.add(match[1]);}
let notices='Boss Assistant MCP third-party notices\n';
for(const name of [...packages].sort()){
 const dir=path.join(root,'node_modules',name),pkg=JSON.parse(await fs.readFile(path.join(dir,'package.json'),'utf8'));
 notices+=`\n${name} ${pkg.version} — ${pkg.license||'See upstream license'}\n`;
 for(const filename of ['LICENSE','LICENSE.md','LICENSE-MIT','LICENSE.txt','license','license.md']){
  try{notices+=await fs.readFile(path.join(dir,filename),'utf8');notices+='\n';break;}catch{}
 }
}
await fs.writeFile(outfile+'.NOTICES.txt',notices);
console.error('Bundled MCP: '+outfile);

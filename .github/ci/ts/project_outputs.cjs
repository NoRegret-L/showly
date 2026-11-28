// List the independent program's actual source closure without type-checking or emitting.
const ts=require('./node_modules/typescript'),fs=require('node:fs'),path=require('node:path');
const projects=JSON.parse(fs.readFileSync(0,'utf8'));
const result=projects.map(dir=>{
 const source=path.join(dir,'sources');
 const roots=JSON.parse(fs.readFileSync(path.join(dir,'roots.json'),'utf8')).map(n=>path.join(source,n));
 const options={strict:true,target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS};
 const program=ts.createProgram(roots,options);
 const files=[];
 for(const f of program.getSourceFiles()){
  if(program.isSourceFileDefaultLibrary(f))continue;
  if(path.dirname(path.resolve(f.fileName))!==source||!f.fileName.endsWith('.ts'))return null;
  if(!f.isDeclarationFile)files.push(path.basename(f.fileName).replace(/\.ts$/,'.js'));
 }
 return files.sort();
});
process.stdout.write(JSON.stringify(result));

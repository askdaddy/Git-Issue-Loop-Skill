#!/usr/bin/env bash
# #37 black-box type guards and explicit family repair. No live platform writes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import os,sys,tempfile,pathlib,subprocess,json
root=pathlib.Path(sys.argv[1]); ops=root/'scripts/git-ops.sh'
with tempfile.TemporaryDirectory() as td:
 w=pathlib.Path(td); bins=w/'bin';bins.mkdir()
 stub=r'''#!/usr/bin/env python3
import os,sys,json,pathlib
args=sys.argv[1:]; tool=pathlib.Path(sys.argv[0]).name
state=pathlib.Path(os.environ['STATE']); calls=pathlib.Path(os.environ['CALLS']); changes=pathlib.Path(os.environ['CHANGES'])
with calls.open('a') as f:f.write(json.dumps([tool,*args])+'\n')
mode=os.environ.get('MODE','ok');target=os.environ.get('TARGET','issue')
n=args[2] if tool!='tea' and len(args)>2 else (args[1] if len(args)>1 else '')
if tool=='tea' and args[:2]==['login','list']:print('https://gitea.example.com user token');sys.exit()
type_probe=(tool=='gh' and args[:2] in [['issue','view'],['pr','view']] and 'number,url' in args) or (tool=='glab' and args[:2]==['issue','view'] and '--jq' in args and '__ILOOP_LABELS_OK__' not in args[args.index('--jq')+1]) or (tool=='tea' and 'index,kind,url' in args)
if type_probe:
 if target=='unavailable':sys.exit(3)
 if tool=='gh' and args[0]=='pr' and target not in ['pr','pr-fallback']:sys.exit(1)
 if target=='pr-fallback' and tool=='gh' and args[0]=='issue':sys.exit(1)
 if tool=='tea':
  if target=='unknown':print('unsupported output');sys.exit()
  k='Issue' if target=='issue' else 'Pull'; segment='issues' if target=='issue' else 'pulls'
  if mode=='wrong-number':n='999'
  if mode=='wrong-kind':k='unknown'
  print('index\tkind\turl');print(f'{n}\t{k}\thttps://gitea.example.com/o/r/{segment}/{n}')
  if mode=='extra-row':print('2\tIssue\thttps://gitea.example.com/o/r/issues/2')
 else:
  print('issue' if target=='issue' else ('pull-request' if target in ['pr','pr-fallback'] else 'unknown'))
 sys.exit()
labels=state.read_text().splitlines()
reading=(tool in ['gh','glab'] and args[:2]==['issue','view']) or (tool=='tea' and len(args)>1 and args[0]=='issues' and args[1]!='edit')
if reading:
 counter=pathlib.Path(os.environ['READS']);i=int(counter.read_text())+1;counter.write_text(str(i))
 if mode=='read-fail' or (mode=='readback-fail' and i>1):sys.exit(4)
 if tool=='gh':print('\n'.join(labels))
 elif tool=='glab':print('__ILOOP_LABELS_OK__');print('\n'.join(labels))
 else:print(json.dumps({'labels':[{'name':s} for s in labels]}))
 sys.exit()
flags={'--remove-label':'remove','--unlabel':'remove','--remove-labels':'remove','--add-label':'add','--label':'add','--add-labels':'add'}
for flag,operation in flags.items():
 if flag not in args:continue
 label=args[args.index(flag)+1]
 with changes.open('a') as f:f.write(json.dumps([operation,label])+'\n')
 if operation=='remove' and mode=='delete-fail':sys.exit(7)
 if operation=='remove' and mode!='retained':labels=[s for s in labels if s!=label]
 if operation=='add' and label not in labels:labels.append(label)
 state.write_text(''.join(s+'\n' for s in labels));sys.exit()
if tool=='tea' and args[:2]==['labels','list']:
 for s in ['p0','p1','p2','p3','riper-research','riper-plan','riper-execute','riper-review','riper-verified','riper-blocked','riper-retry-1']:print('│ 1 │ c0ffee │ '+s+' │ desc │')
'''
 for name in ['gh','glab','tea']:
  p=bins/name;p.write_text(stub);p.chmod(0o755)
 repos={}
 for name,url in [('gh','https://github.com/o/r.git'),('glab','https://gitlab.com/o/r.git'),('tea','https://gitea.example.com/o/r.git')]:
  r=w/name;r.mkdir();subprocess.run(['git','init','-q',str(r)],check=True);subprocess.run(['git','-C',str(r),'remote','add','origin',url],check=True);repos[name]=r
 count=0
 def probe(tool,args,labels=(),role='planner',target='issue',mode='ok',event=False):
  for name,value in [('state',''.join(s+'\n' for s in labels)),('calls',''),('changes',''),('reads','0')]: (w/name).write_text(value)
  env=dict(os.environ,PATH=str(bins)+os.pathsep+os.environ['PATH'],STATE=str(w/'state'),CALLS=str(w/'calls'),CHANGES=str(w/'changes'),READS=str(w/'reads'),TARGET=target,MODE=mode)
  env.pop('GIT_OPS_ROLE',None);env.pop('ILOOP_EVENTS_FD',None)
  cmd=['/bin/bash',str(ops)]+(['--role',role] if role is not None else [])+args
  if event:
   env['ILOOP_EVENTS_FD']='3'
   # Caller-opened fd3, event log is fixture-only temporary output.
   wrapped=['/bin/bash','-c','exec 3>"$1"; shift; exec "$@"','fixture',str(w/'events'),*cmd]
  else:wrapped=cmd
  cp=subprocess.run(wrapped,cwd=repos[tool],env=env,text=True,capture_output=True)
  writes=[json.loads(x) for x in (w/'changes').read_text().splitlines()]
  calls=[json.loads(x) for x in (w/'calls').read_text().splitlines()]
  return cp,set((w/'state').read_text().splitlines()),writes,calls
 def require(ok,msg,cp=None):
  global count
  assert ok,(msg,cp.stdout if cp else '',cp.stderr if cp else '')
  count+=1
 keep=['riper-retry-2','riper-claimed','business','pinned']
 for tool in repos:
  for args in [['issue','priority','1','p2'],['issue','status','1','riper-plan'],['issue','retry','1','incr'],['issue','retry','1','reset'],['issue','priority','1','none'],['issue','status','1','none']]:
   role='reviewer' if args[-1]=='incr' else 'planner'
   for target in ['pr','pr-fallback','unknown','unavailable']:
    cp,l,wr,ca=probe(tool,args,role=role,target=target)
    require(cp.returncode!=0 and not wr,f'{tool} rejects {target} before writes {args}',cp)
    if target in ['pr','pr-fallback']:require('Pull Request' in cp.stderr,f'{tool} PR diagnosis',cp)
  for args in [['issue','priority','1','p2'],['issue','status','1','riper-plan']]:
   cp,l,wr,ca=probe(tool,args)
   require(cp.returncode==0 and wr[-1][0]=='add',f'{tool} positive Issue permits normal set',cp)
  cp,l,wr,ca=probe(tool,['issue','priority','1','none'],['P0','p1','P3',*keep])
  require(cp.returncode==0 and l==set(keep),f'{tool} priority clear preserves other families',cp)
  for role,states in [('planner',['RIPER-RESEARCH','riper-innovation','riper-plan']),('developer',['riper-execute','RIPER-REVIEW','riper-blocked']),('reviewer',['riper-plan','RIPER-VERIFIED','riper-blocked'])]:
   cp,l,wr,ca=probe(tool,['issue','status','1','none'],[*states,'p1',*keep],role=role)
   require(cp.returncode==0 and l==set(['p1',*keep]),f'{tool} status clear {role}',cp)
  for role in ['developer','reviewer',None,'bad']:
   cp,l,wr,ca=probe(tool,['issue','priority','1','none'],['p1'],role=role)
   require(cp.returncode!=0 and not wr,f'{tool} priority clear denies {role}',cp)
  for role in [None,'bad','planner','developer','reviewer']:
   cp,l,wr,ca=probe(tool,['issue','status','1','none'],['riper-research','riper-review','riper-verified'],role=role)
   require(cp.returncode!=0 and not wr,f'{tool} mixed unauthorized states atomic precheck {role}',cp)
  cp,l,wr,ca=probe(tool,['issue','priority','1','none'],keep)
  require(cp.returncode==0 and not wr and l==set(keep),f'{tool} empty clear idempotent',cp)
  for mode in ['read-fail','readback-fail','delete-fail','retained']:
   cp,l,wr,ca=probe(tool,['issue','priority','1','none'],['p1',*keep],mode=mode)
   require(cp.returncode!=0 and '已清空' not in cp.stdout,f'{tool} clear {mode} no false success',cp)
   if mode=='read-fail':require(not wr,f'{tool} initial read failure no writes',cp)
   if mode=='delete-fail':require(len(wr)==1,f'{tool} no removal replay',cp)
  cp,l,wr,ca=probe(tool,['issue','retry','1','get'],['riper-retry-2'],target='unavailable')
  require(cp.returncode==0 and cp.stdout.strip()=='2' and not any('number,url' in c or 'index,kind,url' in c for c in ca),f'{tool} retry get remains read-only',cp)
  for value in ['0','00','-1','1x','https://example.com/issues/1']:
   cp,l,wr,ca=probe(tool,['issue','priority',value,'p1'])
   require(cp.returncode!=0 and not wr and not ca,f'{tool} rejects malformed target {value}',cp)
  cp,l,wr,ca=probe(tool,['issue','label','1','remove','p1'])
  require(cp.returncode!=0 and 'none' in cp.stderr and not wr,f'{tool} direct remove points to explicit clear',cp)
  cp,l,wr,ca=probe(tool,['issue','priority','1','none'],['p1'],event=True)
  evt=json.loads((w/'events').read_text());require(cp.returncode==0 and evt['result']=='success',f'{tool} clear event success compatible',cp)
  cp,l,wr,ca=probe(tool,['issue','status','1','riper-plan'],target='pr',event=True)
  evt=json.loads((w/'events').read_text());require(cp.returncode!=0 and evt['result']=='failed' and evt['rule']=='unknown' and evt['side_effects']=='none',f'{tool} type refusal event does not invent role blame',cp)
 cp,l,wr,ca=probe('gh',['issue','priority','1','none'],['p1'],mode='delete-fail',event=True)
 evt=json.loads((w/'events').read_text());require(cp.returncode!=0 and evt['result']=='failed' and evt['side_effects']=='unknown','first failed removal must not assert known partial completion',cp)
 for mode in ['wrong-number','wrong-kind','extra-row']:
  cp,l,wr,ca=probe('tea',['issue','priority','1','p1'],mode=mode)
  require(cp.returncode!=0 and not wr,'tea malformed typed metadata fails closed',cp)
 print(f'PASS {count} assertions: Issue type, scoped clearing, failure safety, events; gh/glab/tea fixtures')
PY

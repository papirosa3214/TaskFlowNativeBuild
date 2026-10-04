#!/opt/homebrew/bin/python3
"""Dedicated TaskFlow builder SSH gateway. No general shell entry."""
import os, shlex, subprocess, sys, json
from pathlib import Path
from datetime import datetime, timezone
ROOT=Path('/Users/max/Проекты/TaskFlowDeveloper').resolve()
LOG=Path('/Users/max/Library/Logs/TaskFlowDeveloper/access.jsonl')
os.environ['PATH']='/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
os.chdir(ROOT)
args=shlex.split(os.environ.get('SSH_ORIGINAL_COMMAND',''))
allowed={'mcp','prepare','status','diff','read','write','commit','push'}
if not args or args[0] not in allowed:
 print('Only TaskFlow developer gateway commands are allowed.',file=sys.stderr);sys.exit(126)
LOG.parent.mkdir(parents=True,exist_ok=True)
with LOG.open('a') as f:f.write(json.dumps({'at':datetime.now(timezone.utc).isoformat(),'command':args[0],'peer':os.environ.get('SSH_CONNECTION','').split(' ')[0]})+'\n')
def file_arg():
 if len(args)!=2:raise ValueError('Expected one relative file path')
 p=(ROOT/args[1]).resolve()
 if not p.is_relative_to(ROOT) or '.git' in p.relative_to(ROOT).parts:raise ValueError('Path outside developer checkout')
 return p
try:
 if args[0]=='mcp':
  if len(args)!=1:raise ValueError('Unexpected arguments')
  os.execv('/opt/homebrew/bin/xcodebuildmcp',['xcodebuildmcp','mcp'])
 elif args[0]=='prepare':
  subprocess.run(['/opt/homebrew/bin/xcodegen','generate'],check=True)
 elif args[0]=='status':subprocess.run(['/usr/bin/git','status','--short','--branch'],check=True)
 elif args[0]=='commit':
  data=json.loads(sys.stdin.read());paths=data['paths']
  if not paths:raise ValueError('Explicit changed files required')
  for name in paths:
   target=(ROOT/name).resolve()
   if not target.is_relative_to(ROOT) or '.git' in target.relative_to(ROOT).parts:raise ValueError('Path outside checkout')
  branch=subprocess.check_output(['/usr/bin/git','branch','--show-current'],text=True).strip()
  if not branch.startswith('codex/'):raise ValueError('Only developer codex branches allowed')
  subprocess.run(['/usr/bin/git','add','--',*paths],check=True)
  subprocess.run(['/usr/bin/git','commit','-m',data['message']],check=True)
 elif args[0]=='push':
  branch=subprocess.check_output(['/usr/bin/git','branch','--show-current'],text=True).strip()
  if not branch.startswith('codex/'):raise ValueError('Only developer codex branches allowed')
  subprocess.run(['/usr/bin/git','push','origin',branch],check=True)
 elif args[0]=='diff':subprocess.run(['/usr/bin/git','diff'],check=True)
 elif args[0]=='read':sys.stdout.write(file_arg().read_text())
 elif args[0]=='write':
  p=file_arg();content=sys.stdin.buffer.read(2*1024*1024+1)
  if len(content)>2*1024*1024:raise ValueError('File too large')
  p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(content);print('Written',p.relative_to(ROOT))
except Exception as e:
 print(str(e),file=sys.stderr);sys.exit(1)

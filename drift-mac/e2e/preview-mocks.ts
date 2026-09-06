export function previewMocks(seed: Record<string, string> = {}) {
  return `
    const saved = localStorage.getItem('test-fs');
    window.__mockFS = new Map(Object.entries(saved ? JSON.parse(saved) : ${JSON.stringify(seed)}));
    window.__openedUrls=[]; window.__failOpen=false; window.__dragged=false; window.__commands = []; window.__presented=false; window.__quitAck=false; window.__writes = []; window.__delay = 0; window.__readDelay=0; window.__failRead=false; window.__failList=false; window.__failSave=false; window.__recoveryDrafts=[]; window.__events = new Map(); window.__callbacks = {}; window.__destroyed=false;
    const persist=()=>localStorage.setItem('test-fs',JSON.stringify(Object.fromEntries(window.__mockFS)));
    const stem=s=>(s.split('\\n').find(s=>s.trim())||'Untitled').replace(/^#+\\s*/,'').replace(/[<>:"/\\\\|?*]/g,'').slice(0,70).trim()||'Untitled';
    window.__TAURI_INTERNALS__ = {
      metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},
      transformCallback:(fn)=>{const id=crypto.randomUUID();window.__callbacks[id]=fn;return id},
      unregisterCallback:()=>{},
      invoke:async(cmd,args={})=>{
        window.__commands.push(cmd);
        if(cmd==='plugin:shell|open'){if(window.__failOpen)throw 'No browser available';window.__openedUrls.push(args.path);return;}
        if(cmd==='plugin:window|start_dragging'){window.__dragged=true;return;}
        if(cmd==='window_ready'){window.__presented=true;return true;}
        if(cmd==='quit_ready'){window.__quitAck=true;return;}
        if(cmd==='cancel_quit'){window.__emit('quit-cancelled');return;}
        if(cmd==='notebook_info'){if(window.__bootDelay)await new Promise(r=>setTimeout(r,window.__bootDelay));return {directory:'/isolated/Notebook',drafts:window.__recoveryDrafts,restoreDrafts:window.__restoreDrafts ?? (window.__TAURI_INTERNALS__.metadata.currentWindow.label==='main')};}
        if(cmd==='list_notes'){if(window.__failList)throw 'Drift does not have permission to open the notebook. Allow access in Files and Folders, then try again.';return Array.from(window.__mockFS,([path,text])=>({path,title:path.replace(/\\.md$/,''),modified:1000000,size:text.length}));}
        if(cmd==='read_note'){if(window.__readDelay)await new Promise(r=>setTimeout(r,window.__readDelay));if(window.__failRead)throw 'Drift does not have permission to open the notebook. Allow access in Files and Folders, then try again.';if(!window.__mockFS.has(args.path))throw 'Missing file';return window.__mockFS.get(args.path)}
        if(cmd==='save_note'){
          const d=args.draft;window.__writes.push({...d});
          if(window.__delay)await new Promise(r=>setTimeout(r,window.__delay));
          if(window.__failSave)throw 'Disk unavailable';
          const disk=d.path?window.__mockFS.get(d.path):undefined;
          let path=d.path,conflict=false;
          if(!path&&!d.text.trim())return {path:null,text:d.text,conflict:false};
          if(path&&disk!==d.baseline&&disk!==d.text){path=null;conflict=true;}
          const renamed=path&&disk!==undefined&&d.text.trim()&&stem(d.text)!==stem(disk);
          if(!path||renamed){const old=path;const name=stem(d.text)+(conflict?' (conflict)':'');path=name+'.md';let i=1;while(window.__mockFS.has(path))path=name+' '+i+++'.md';if(renamed)window.__mockFS.delete(old);}
          window.__mockFS.set(path,d.text);persist();return {path,text:d.text,conflict};
        }
        if(cmd==='plugin:event|listen'){window.__events.set(args.event,window.__callbacks[args.handler]);return args.handler}
        if(cmd==='plugin:event|unlisten')return;
        if(cmd==='plugin:window|destroy'){window.__destroyed=true;return}
        if(cmd==='window_for_note')return null;
        return null;
      }
    };
    window.__emit=(name,payload)=>window.__events.get(name)?.({payload});
    window.__persist=persist;
  `;
}

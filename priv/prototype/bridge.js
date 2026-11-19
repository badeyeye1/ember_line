/* The page crawler from docs/design/prototype.html (BRIDGE), injected into a loaded prototype that is
   served sandboxed by EmberLineWeb.PrototypeController. It talks to the board through postMessage only. */
(function(){
var norm=function(t){return String(t||"").toLowerCase().replace(/\(.*?\)/g," ").replace(/[^a-z0-9 ]+/g," ").replace(/\s+/g," ").trim()};
var generic=/\b(button|btn|link|list|bar|field|form|section|panel|card|area|page|tab|modal|dialog|header|the|and|my|screen|view)\b/g;
var st=document.createElement("style");st.textContent=".em-hl{outline:3px solid #2563eb!important;outline-offset:2px;border-radius:4px;box-shadow:0 0 0 7px rgba(37,99,235,.22)!important}";
var CLICKABLE='button,a,[role=button],[role=tab],[role=link],[role=menuitem],[role=option],input[type=submit],input[type=button],summary,label,li,[onclick],[tabindex]';
function visible(el){var r=el.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(el).visibility!=="hidden"}
function findClick(text){var k=norm(text);if(!k)return null;var all=[].slice.call(document.querySelectorAll(CLICKABLE)),c=all.filter(visible),best=null;
 var hit=pick(c,k)||pick(all,k,true);if(hit)return hit;
 var any=[].slice.call(document.querySelectorAll("div,span,p,h1,h2,h3,h4")).filter(visible);
 any.forEach(function(el){var t=norm(el.textContent);if(t===k&&(!best||t.length<best.l))best={el:el,l:t.length}});
 return best&&best.el}
/* Best text match among elements; for hidden ones (collapsed menus, off-screen rails) accept only exact or prefix matches. */
function pick(c,k,strict){var best=null;
 c.forEach(function(el){var t=norm(el.textContent||el.value||el.getAttribute("aria-label")||el.title);if(!t)return;
  var score=t===k?0:t.indexOf(k)===0?1:t.indexOf(k)>=0?2:(k.indexOf(t)>=0&&t.length>3)?3:9;
  if(strict&&score>1)return;
  if(score<9&&(!best||score<best.s||score===best.s&&t.length<best.l))best={el:el,s:score,l:t.length}});
 return best&&best.el}
/* Fields are matched by label, placeholder, name, id or aria-label; visible ones first, then hidden ones (e.g. a role switcher in a collapsed rail). */
function findField(name){var k=norm(name),all=[].slice.call(document.querySelectorAll("input,textarea,select"));
 function m(list){for(var i=0;i<list.length;i++){var el=list[i],lab=el.id&&document.querySelector('label[for="'+el.id+'"]');
  var t=norm([el.placeholder,el.name,el.id,el.getAttribute("aria-label"),lab&&lab.textContent,el.closest("label")&&el.closest("label").textContent].join(" "));
  if(t.indexOf(k)>=0)return el}return null}
 return m(all.filter(visible))||m(all)}
function setVal(el,v){
 if(el.tagName==="SELECT"){var o=[].slice.call(el.options),nv=norm(v),hit=null;
  o.forEach(function(x){if(!hit&&x.value===v)hit=x});
  o.forEach(function(x){if(!hit&&norm(x.textContent)===nv)hit=x});
  o.forEach(function(x){if(!hit&&nv&&(norm(x.textContent).indexOf(nv)>=0||norm(x.value).indexOf(nv)>=0))hit=x});
  if(hit)v=hit.value}
 var p=el.tagName==="TEXTAREA"?HTMLTextAreaElement.prototype:el.tagName==="SELECT"?HTMLSelectElement.prototype:HTMLInputElement.prototype;
 var d=Object.getOwnPropertyDescriptor(p,"value");d&&d.set?d.set.call(el,v):el.value=v;
 el.dispatchEvent(new Event("input",{bubbles:true}));el.dispatchEvent(new Event("change",{bubbles:true}))}
function press(el){["pointerdown","mousedown","pointerup","mouseup"].forEach(function(t){try{el.dispatchEvent(new MouseEvent(t,{bubbles:true}))}catch(e){}});el.click()}
function nav(name){var k=norm(name).replace(generic," ").replace(/\s+/g," ").trim();if(!k)return false;var el=findClick(k);if(el){press(el);return true}return false}
/* Run the steps Claude worked out for reaching a screen: click visible text, fill fields, set a hash route, wait. */
function run(steps,i,done){if(i>=steps.length)return done(true);var s=steps[i]||{},tries=0;
 (function attempt(){var ok=false;
  try{if(s.hash){location.hash=s.hash;ok=true}
   else if(s.wait){ok=true}
   else if(s.css){var c=document.querySelector(s.css);if(c){press(c);ok=true}}
   else if(s.fill){var f=findField(s.fill.field||"");if(f){setVal(f,String(s.fill.value==null?"":s.fill.value));ok=true}}
   else if(s.click){var el=findClick(s.click);if(el){press(el);ok=true}}
   else ok=true}catch(e){}
  if(ok)return setTimeout(function(){run(steps,i+1,done)},s.wait?Math.min(+s.wait||300,3000):350);
  if(tries++<14)return setTimeout(attempt,250);
  done(false,s.click||s.css||(s.fill&&s.fill.field)||s.hash||"step "+(i+1))})()}
function hl(text){document.querySelectorAll(".em-hl").forEach(function(e){e.classList.remove("em-hl")});if(!text)return true;
 var n=norm(text),keys=[n,n.replace(generic," ").replace(/\s+/g," ").trim(),n.split(" ").slice(0,2).join(" ")].filter(function(k){return k.length>1});
 var groups=["button,a,input,select,textarea,label,[role=button],[role=tab]","h1,h2,h3,h4,li,p,span,div,section,ul,ol,table,form"],best=null;
 for(var g=0;g<groups.length&&!best;g++){var els=[].slice.call(document.querySelectorAll(groups[g]));
 for(var j=0;j<keys.length&&!best;j++)els.forEach(function(el){var t=norm(el.textContent||el.value||el.placeholder);if(t&&t.indexOf(keys[j])>=0&&(!best||t.length<best.l))best={el:el,l:t.length}});}
 if(!best)return false;if(!st.isConnected)document.head.appendChild(st);best.el.classList.add("em-hl");
 var r=best.el.getBoundingClientRect();window.scrollTo(0,Math.max(0,r.top+scrollY-innerHeight/3));return true}
/* In a srcdoc frame, "#route" links resolve against the parent page's address, so following one would load the parent
   page into the frame. Turn unhandled hash links into in-place route changes, and keep unhandled form posts in the frame. */
addEventListener("click",function(e){if(e.defaultPrevented)return;var a=e.target&&e.target.closest&&e.target.closest("a[href]");if(!a)return;
 var h=a.getAttribute("href")||"";if(h.charAt(0)==="#"){e.preventDefault();if(h.length>1&&location.hash!==h)location.hash=h}
 else if(!/^(https?:|mailto:|tel:)/i.test(h)){e.preventDefault()}});
addEventListener("submit",function(e){if(!e.defaultPrevented)e.preventDefault()});
var started=false;
addEventListener("message",function(e){var d=e.data||{};if(d.t!=="em"||started)return;started=true;
 var steps=Array.isArray(d.steps)?d.steps:null;
 function report(ok,miss,how,found){parent.postMessage({t:"em-nav",ok:ok,miss:miss||"",how:how,found:!!found},"*")}
 function light(navOk,miss,how){var tries=0;(function go(){var found=d.text&&hl(d.text);
  if(found||!d.text)return report(navOk,miss,how,!!found);
  if(tries++<12)return setTimeout(go,300);report(navOk,miss,how,false)})()}
 if(steps&&steps.length){setTimeout(function(){run(steps,0,function(ok,miss){light(ok,miss,"steps")})},400)}
 else if(steps){setTimeout(function(){light(true,"","start")},400)}
 else{var tries=0;(function go(){if(d.screen&&nav(d.screen))return setTimeout(function(){light(true,"","name")},400);if(tries++<8)return setTimeout(go,300);light(false,d.screen,"name")})()}});
/* ---- page splitter: walk every role and every route of the running prototype and snapshot each distinct page ---- */
function wait(ms){return new Promise(function(r){setTimeout(r,ms)})}
function djb(s){var h=5381;for(var i=0;i<s.length;i++)h=(h*33+s.charCodeAt(i))|0;return h}
function sig(){var m=document.querySelector("main,#view,#root,#app,[role=main]")||document.body;var t=(m.innerText||"").replace(/[0-9]/g,"");return djb(t.slice(0,6000))}
function typeOf(r){return String(r||"").replace(/-[a-z]*[0-9][a-z0-9]*(-[a-z0-9]+)*$/i,"-*")}
function heading(){var h=[].slice.call(document.querySelectorAll("main h1,#view h1,h1,h2")).filter(visible)[0];return ((h&&h.textContent)||document.title||"page").replace(/[ \n\t]+/g," ").trim().slice(0,60)}
function slug(s){return String(s||"").toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,"").slice(0,40)||"page"}
function snap(){var src=[].slice.call(document.querySelectorAll("input,textarea,select"));var c=document.documentElement.cloneNode(true);
 var dst=[].slice.call(c.querySelectorAll("input,textarea,select"));
 src.forEach(function(el,i){var d=dst[i];if(!d)return;if(el.tagName==="SELECT"){[].slice.call(d.options).forEach(function(o,j){if(el.options[j]&&el.options[j].selected)o.setAttribute("selected","")})}
  else if(el.type==="checkbox"||el.type==="radio"){if(el.checked)d.setAttribute("checked","")}else if(el.tagName==="TEXTAREA"){d.textContent=el.value}else d.setAttribute("value",el.value)});
 [].slice.call(c.querySelectorAll("script,iframe,noscript,object,embed")).forEach(function(n){n.remove()});
 [].slice.call(c.querySelectorAll(".em-hl")).forEach(function(n){n.classList.remove("em-hl")});
 [].slice.call(c.querySelectorAll("[role=status],[aria-live],#toast,.toast")).forEach(function(n){n.textContent="";n.classList.remove("show","on","open","visible")});
 if(st.isConnected){var s2=[].slice.call(c.querySelectorAll("style")).filter(function(s){return s.textContent===st.textContent});s2.forEach(function(n){n.remove()})}
 return "<!doctype html>\n"+c.outerHTML}
function roleSelect(){var re=/persona|\brole\b|viewing|view as|signed in as|acting as|perspective|\buser\b/i,no=/project|workspace|stack|storage|theme|language|time ?zone|sort|filter/i;
 var s=[].slice.call(document.querySelectorAll("select")).filter(function(el){var lab=el.id&&document.querySelector('label[for="'+el.id+'"]');
  var t=[el.id,el.name,el.getAttribute("aria-label"),lab&&lab.textContent,el.closest("label")&&el.closest("label").textContent].join(" ");return re.test(t)&&!no.test(t)&&!el.disabled&&el.options.length>1&&el.options.length<=40});
 return s[0]||null}
function fieldLabel(el){var lab=el.id&&document.querySelector('label[for="'+el.id+'"]');return ((lab&&lab.textContent)||el.getAttribute("aria-label")||el.name||el.id||"").trim()}
function routes(){var seen={},out=[];[].slice.call(document.querySelectorAll('a[href^="#"]')).forEach(function(a){var h=a.getAttribute("href");if(h.length>1&&!seen[h]&&!/^#(top|main|content|skip)/i.test(h)){seen[h]=1;out.push(h)}});return out.slice(0,40)}
function navButtons(){var seen={},out=[];[].slice.call(document.querySelectorAll("nav button,[role=tablist] [role=tab],header button,aside button,nav [role=link],[role=menubar] [role=menuitem]")).forEach(function(b){var t=norm(b.textContent);if(t&&t.length>2&&t.length<40&&!seen[t]&&!/sign out|log ?out|delete|remove|reset|cancel/.test(t)){seen[t]=1;out.push(b.textContent.trim())}});return out.slice(0,25)}
/* Dedupe rules: identical content is one page (redirects land here); the same heading on the same kind of route is one
   screen even when another role sees it; detail routes like #trade-t223 keep one example per kind; a role whose menu is
   the same as one already walked (another student, say) is skipped. */
async function crawl(max){var pages=[],seenSig={},seenScreen={},seenMenu={},rs=roleSelect(),ctxs=[{label:"",value:null}];
 if(rs){var cur=rs.value;[].slice.call(rs.options).forEach(function(o){if(o.value!==cur)ctxs.push({label:o.textContent.trim(),value:o.value})});ctxs[0].label=(rs.options[rs.selectedIndex]||{}).textContent||"default";ctxs[0].value=cur}
 var field=rs?fieldLabel(rs):"";
 async function take(ctx,how){var g=sig();if(seenSig[g])return;seenSig[g]=1;var h=heading();
  var sk=norm(h)+"|"+typeOf(how.route||"");if(seenScreen[sk])return;seenScreen[sk]=1;
  var file=(ctx.label?slug(ctx.label)+"--":"")+slug(how.route||h)+".html";var n=2;while(pages.some(function(p){return p.file===file}))file=file.replace(/(-\d+)?\.html$/,"-"+(n++)+".html");
  var steps=[];if(rs&&ctx.value!=null)steps.push({fill:{field:field,value:ctx.value}});if(how.route)steps.push({hash:how.route});if(how.click)steps.push({click:how.click});
  var p={file:file,title:h,role:ctx.label,route:how.route||"",steps:steps,html:snap()};pages.push(p);parent.postMessage({t:"em-page",page:p,count:pages.length},"*")}
 for(var c=0;c<ctxs.length&&pages.length<max;c++){var ctx=ctxs[c];
  if(rs&&ctx.value!=null){var sel=roleSelect()||rs;setVal(sel,ctx.value);await wait(700)}
  parent.postMessage({t:"em-crawl-progress",role:ctx.label,index:c+1,of:ctxs.length,count:pages.length},"*");
  var rt=routes(),menu=rt.filter(function(r){return typeOf(r)===r}).sort().join(",")+"|"+navButtons().join(",");
  if(c>0&&seenMenu[menu])continue;seenMenu[menu]=1;
  await take(ctx,{route:location.hash||""});
  var kinds={};
  for(var i=0;i<rt.length&&pages.length<max;i++){var k=typeOf(rt[i]);if(kinds[k])continue;kinds[k]=1;
   try{location.hash=rt[i]}catch(e){}await wait(450);await take(ctx,{route:rt[i]});
   if(i<rt.length-1){var more=routes();more.forEach(function(r){if(rt.indexOf(r)<0&&rt.length<60)rt.push(r)})}}
  var nb=navButtons();for(var j=0;j<nb.length&&pages.length<max;j++){var b=findClick(nb[j]);if(!b)continue;var before=location.hash;press(b);await wait(450);
   await take(ctx,location.hash!==before?{route:location.hash}:{click:nb[j]});
   try{document.dispatchEvent(new KeyboardEvent("keydown",{key:"Escape",bubbles:true}))}catch(e){}await wait(150)}
 }
 parent.postMessage({t:"em-crawl-done",count:pages.length,roles:ctxs.length},"*")}
addEventListener("message",function(e){var d=e.data||{};if(d.t==="em-snap"){parent.postMessage({t:"em-snapped",html:snap()},"*");return}if(d.t==="em-crawl"&&!started){started=true;setTimeout(function(){crawl(d.max||40).catch(function(err){parent.postMessage({t:"em-crawl-done",count:-1,error:String(err&&err.message||err)},"*")})},900)}});
parent.postMessage({t:"em-ready"},"*");})();
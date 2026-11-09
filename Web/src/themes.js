// Each theme is a set of CSS variables. Editor + syntax colours all read these.
const T = (dark, v) => ({ dark, vars: v });
export const THEMES = {
  'Dark Modern': T(true,  { bg:'#1f1f1f', fg:'#cccccc', gutterFg:'#6e7681', sel:'#264f78', line:'#2a2d2e', cursor:'#aeafad', kw:'#569cd6', ctl:'#c586c0', str:'#ce9178', num:'#b5cea8', type:'#4ec9b0', fn:'#dcdcaa', com:'#6a9955', pre:'#c586c0', vr:'#9cdcfe', bar:'#181818', border:'#2b2b2b', accent:'#0078d4' }),
  'Dark+':        T(true,  { bg:'#1e1e1e', fg:'#d4d4d4', gutterFg:'#858585', sel:'#264f78', line:'#282828', cursor:'#aeafad', kw:'#569cd6', ctl:'#c586c0', str:'#ce9178', num:'#b5cea8', type:'#4ec9b0', fn:'#dcdcaa', com:'#6a9955', pre:'#c586c0', vr:'#9cdcfe', bar:'#252526', border:'#333333', accent:'#007acc' }),
  'Light Modern': T(false, { bg:'#ffffff', fg:'#3b3b3b', gutterFg:'#6e7681', sel:'#add6ff', line:'#f3f3f3', cursor:'#005fb8', kw:'#0000ff', ctl:'#af00db', str:'#a31515', num:'#098658', type:'#267f99', fn:'#795e26', com:'#008000', pre:'#af00db', vr:'#001080', bar:'#f8f8f8', border:'#e5e5e5', accent:'#005fb8' }),
  'One Dark':     T(true,  { bg:'#282c34', fg:'#abb2bf', gutterFg:'#636d83', sel:'#3e4451', line:'#2c313c', cursor:'#528bff', kw:'#c678dd', ctl:'#c678dd', str:'#98c379', num:'#d19a66', type:'#e5c07b', fn:'#61afef', com:'#5c6370', pre:'#e06c75', vr:'#e06c75', bar:'#21252b', border:'#181a1f', accent:'#61afef' }),
  'Dracula':      T(true,  { bg:'#282a36', fg:'#f8f8f2', gutterFg:'#6272a4', sel:'#44475a', line:'#2f3140', cursor:'#f8f8f0', kw:'#ff79c6', ctl:'#ff79c6', str:'#f1fa8c', num:'#bd93f9', type:'#8be9fd', fn:'#50fa7b', com:'#6272a4', pre:'#ff79c6', vr:'#f8f8f2', bar:'#21222c', border:'#191a21', accent:'#bd93f9' }),
  'Monokai':      T(true,  { bg:'#272822', fg:'#f8f8f2', gutterFg:'#90908a', sel:'#49483e', line:'#3e3d32', cursor:'#f8f8f0', kw:'#f92672', ctl:'#f92672', str:'#e6db74', num:'#ae81ff', type:'#66d9ef', fn:'#a6e22e', com:'#75715e', pre:'#f92672', vr:'#f8f8f2', bar:'#1e1f1c', border:'#34352f', accent:'#a6e22e' }),
  'GitHub Dark':  T(true,  { bg:'#0d1117', fg:'#c9d1d9', gutterFg:'#6e7681', sel:'#264f78', line:'#161b22', cursor:'#58a6ff', kw:'#ff7b72', ctl:'#ff7b72', str:'#a5d6ff', num:'#79c0ff', type:'#ffa657', fn:'#d2a8ff', com:'#8b949e', pre:'#ff7b72', vr:'#c9d1d9', bar:'#010409', border:'#21262d', accent:'#58a6ff' }),
};
export const DEFAULT_THEME = 'Dark Modern';

export function applyTheme(name) {
  const th = THEMES[name] || THEMES[DEFAULT_THEME];
  const r = document.documentElement.style;
  for (const [k, v] of Object.entries(th.vars)) r.setProperty('--' + k, v);
  r.setProperty('--err', th.dark ? '#f85149' : '#d1242f');
  r.setProperty('--errbg', th.dark ? 'rgba(248,81,73,.16)' : 'rgba(209,36,47,.10)');
  r.setProperty('--warn', th.dark ? '#d29922' : '#9a6700');
  r.setProperty('--warnbg', th.dark ? 'rgba(210,153,34,.14)' : 'rgba(154,103,0,.10)');
  document.documentElement.style.colorScheme = th.dark ? 'dark' : 'light';
  return th.dark;
}

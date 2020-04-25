if ! exists('g:lightline')
  let g:lightline = {}
endif
if ! has_key(g:lightline, 'component')
  let g:lightline.component = {}
endif
if ! has_key(g:lightline, 'component_visible_condition')
  let g:lightline.component_visible_condition = {}
endif
let g:lightline.colorscheme = 'seoul256'
let g:lightline.component.anzu     = '%{anzu#search_status()}'
let g:lightline.component.fugitive = '%{fugitive#head()}'
let g:lightline.component_visible_condition.fugitive = '(exists("*fugitive#head") && ""!=fugitive#head())'
let g:lightline.active = {
      \ 'right': [
      \   ['syntastic', 'lineinfo'],
      \   ['percent'],
      \   ['fileformat', 'fileencoding', 'filetype'],
      \ ],
      \ 'left' : [
      \   ['mode', 'paste'],
      \   ['fugitive'],
      \   ['readonly', 'filename', 'modified'],
      \   ['ale']
      \ ],
      \ }
let g:lightline.component_expand = {
      \ 'syntastic' : 'SyntasticStatuslineFlag',
      \ }
let g:lightline.component_type = {
      \ 'syntastic' : 'error',
      \ }
let g:lightline.component_function = {
      \ 'ale' : 'ALEGetStatusLine',
      \ }
let g:lightline.tabline = {
      \ 'left': [ ['tabs'] ],
      \ }
let g:lightline.tab = {
      \ 'active'   : ['tabnum', 'readonly', 'filename', 'modified'],
      \ 'inactive' : ['tabnum', 'readonly', 'filename', 'modified'],
      \ }

function! s:split_cmdline(cmdline, cmdpos)
  let l:res = [
    \   (' ' . a:cmdline)[:a:cmdpos - 1][1:],
    \   (' ' . a:cmdline)[a:cmdpos - 1:][1:]
    \ ]
  return l:res
endfunction

" emacs-style word-wise movement/deletion in command-line mode
function! user#fn#cmdlineMoveWord(dir, del)
  let l:cmdline = getcmdline()
  let l:cmdpos = getcmdpos()
  let l:pat = '^\s*\W*\S\{-}\($\|\w\@<=\([^a-zA-Z0-9]\|\s\|\>\)\@<=\)'
  if a:dir == 1
    let l:cl = s:split_cmdline(cmdline, cmdpos)
    let l:cmdline_r_post = substitute(l:cl[1], l:pat, '', '')
    if a:del == 1
      let l:cmdline_new = l:cl[0] . l:cmdline_r_post
      return l:cmdline_new
    else
      let l:cmdlen_r = len(l:cl[1])
      let l:cmdlen_r_post = len(l:cmdline_r_post)
      let l:cmdlen_r_diff = l:cmdlen_r - l:cmdlen_r_post
      let l:newcmdpos = l:cmdpos + l:cmdlen_r_diff
      call setcmdpos(l:newcmdpos)
      return l:cmdline
    endif
  elseif a:dir == -1
    let l:cmdline_rev = join(reverse(split(l:cmdline, '.\@=')), '')
    let l:cmdpos_rev = len(l:cmdline) - l:cmdpos + 2
    let l:cl_rev = s:split_cmdline(cmdline_rev, cmdpos_rev)
    let l:cmdline_rev_r_post = substitute(l:cl_rev[1], l:pat, '', '')
    let l:cmdlen_rev_r = len(l:cl_rev[1])
    let l:cmdlen_rev_r_post = len(l:cmdline_rev_r_post)
    let l:cmdlen_rev_r_diff = l:cmdlen_rev_r - l:cmdlen_rev_r_post
    let l:newcmdpos = l:cmdpos - l:cmdlen_rev_r_diff
    call setcmdpos(l:newcmdpos)
    if a:del == 1
      let l:cmdline_rev_new = l:cl_rev[0] . l:cmdline_rev_r_post
      let l:cmdline_new = join(reverse(split(l:cmdline_rev_new, '.\@=')), '')
      return l:cmdline_new
    else
      return l:cmdline
    endif
  endif
  throw 'invalid direction ' . a:dir
endfunction

function! user#fn#manSectionMove(direction, mode, count)
  norm! m'
  if a:mode ==# 'v'
    norm! gv
  endif
  let i = 0
  while i < a:count
    let i += 1
    " saving current position
    let line = line('.')
    let col  = col('.')
    let pos = search('^\a\+', 'W'.a:direction)
    " if there are no more matches, return to last position
    if pos == 0
      call cursor(line, col)
      return
    endif
  endwhile
endfunction

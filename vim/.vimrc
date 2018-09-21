" settings
syntax enable
set background=dark
colorscheme elflord
filetype plugin indent on
set paste
set laststatus=2
set hlsearch
set ttimeoutlen=50
runtime macros/matchit.vim

" statusline foo
set ls=2
set statusline=
set statusline +=%1*\ \[b:%n\]\ %*      "buffer number
set statusline +=%1*\[%{&ff}\/%*        "file format
set statusline +=%1*%{strlen(&fenc)?&fenc:&enc}\]\ %*   "encoding
set statusline +=%3*%y%*                "file type
set statusline +=%4*\ %<%t%*            "current file
set statusline +=%2*%m%*                "modified flag
set statusline +=%1*%=%5l%*             "current line
set statusline +=%2*/%L%*               "total lines
set statusline +=%1*%4v\ %*             "virtual column number
set statusline +=%1*%P\ %*              " percentage of file

" Return to last edit position when opening files
autocmd BufReadPost *
  \ if line("'\"") > 0 && line("'\"") <= line("$") |
  \   exe "normal! g`\"" |
  \ endif

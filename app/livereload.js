let livereload = require('livereload')
let server = livereload.createServer({
    exts: [ 'js', 'ts', 'php', 'twig', 'html']
})
server.watch(`/var/www/`)

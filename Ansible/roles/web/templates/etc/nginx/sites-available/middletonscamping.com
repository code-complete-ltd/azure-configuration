server {
    listen 80;
    listen [::]:80;
    server_name middletonscamping.com middletonscamping.co.uk;
    root {{ web_root }}/middletonscamping.com;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name www.middletonscamping.com www.middletonscamping.co.uk;
    rewrite ^/(.*)$ http://middletonscamping.com/$1 permanent;
}

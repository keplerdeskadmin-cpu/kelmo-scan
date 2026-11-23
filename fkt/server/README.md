# Kepler Messenger — server

Staff chat server for Fly Kawn Travel. Node 18+ only, no npm packages.

## Chalana (laptop par)
```
cd ~/fkt-server
node server.js
```
- Terminal mein **admin key** likha aata hai.
- Admin panel: http://localhost:3100/admin (key daal kar kholein).
- Staff add karein (naam + phone). Wohi number app mein login kar sakte hain.
- SMS set na ho to login ka 6-digit code admin panel mein "Login codes" mein nazar aata hai.

Office WiFi par app mein server address: `http://<laptop-IP>:3100` (`hostname -I` se IP).
Data: `data/` folder (users, chats, messages, files). Backup ke liye yahi folder copy karein.

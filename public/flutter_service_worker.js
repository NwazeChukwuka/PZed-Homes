'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "4a94801da5eac6d8bd387a372ce70e49",
"assets/AssetManifest.bin.json": "34873b7e3986e553e15a6bb340958e8b",
"assets/AssetManifest.json": "f42aa7ac7ee5bdb549fec189a977fe07",
"assets/assets/images/Classic%2520Room/Classic%25201.JPG": "cbb797119d1f3ffa95a709a90499fb9a",
"assets/assets/images/Classic%2520Room/Classic%25202.png": "1cf0a28739d35edc4cb8023fb937494c",
"assets/assets/images/Classic%2520Room/Classic%25203.JPG": "2e41d48416a3dbcb45fc246dbf81f967",
"assets/assets/images/Classic%2520Room/Classic%25204.JPG": "3c162809b54b751d0d843146e00198b4",
"assets/assets/images/Classic%2520Room/Classic%25205.jpg": "5c821259f2b1e899d439b459c1545356",
"assets/assets/images/Deluxe%2520Room/Deluxe%25201.JPG": "8e88b7a2dd5e7c461a8e1bb6bfd9142b",
"assets/assets/images/Deluxe%2520Room/Deluxe%25202.JPG": "e3cd5b614c2cf1ba76078688d37cbfd2",
"assets/assets/images/Deluxe%2520Room/Deluxe%25203.png": "d151f344d7a29249ffe7d1767f87af6c",
"assets/assets/images/Deluxe%2520Room/Deluxe%25204.JPG": "cce8baa367318f9d8cad3260e39c4c7b",
"assets/assets/images/Diplomatic%2520Room/Diplomatic%25201.png": "caac96b982ac230dc5faa506cae87dc0",
"assets/assets/images/Diplomatic%2520Room/Diplomatic%25202.JPG": "e4c3c03659b1c5120e163a364c6c9162",
"assets/assets/images/Diplomatic%2520Room/Diplomatic%25203.jpg": "bceb61ea3314e44a0232cd2c6e7f7a38",
"assets/assets/images/Executive%2520Room/Executive%25201.png": "00e9398bf959fb5b49be0ec35e24e9ff",
"assets/assets/images/Executive%2520Room/Executive%25202.png": "d9aaeabdab515ec84fb28a74c223083c",
"assets/assets/images/Executive%2520Room/Executive%25203.jpg": "f88c3c6c79128813cba9c961d1c31a3b",
"assets/assets/images/Front%2520View/Front%2520View%25201.JPG": "552dd775e0dbd952b5829b5b9766ce69",
"assets/assets/images/Front%2520View/Front%2520View%25202.JPG": "9a238124d9a007f45633f7dce3c47c92",
"assets/assets/images/Front%2520View/Front%2520View%25203.jpg": "6520711df50d202cd0b2423440a16785",
"assets/assets/images/Front%2520View/Front%2520View%25204.jpg": "3a1dddcef22ffd9177f6df32691714af",
"assets/assets/images/Front%2520View/Front%2520View%25205.JPG": "7b8420e441f9ca2291a2afa676197cda",
"assets/assets/images/Front%2520View/Front%2520View%25206.jpg": "8160f94903c18fbfebc9873f100b159f",
"assets/assets/images/Outside%2520bar/Outside%2520Bar%25201.JPG": "2c1322c08416129c204ef5ce048d0e7f",
"assets/assets/images/Outside%2520bar/Outside%2520Bar%25202.jpg": "07568f6c5e9bbf2b9c138ffd2df6680e",
"assets/assets/images/Outside%2520bar/Outside%2520Bar%25203.JPG": "8017dce093f8d1c0608a83918c782486",
"assets/assets/images/Passage/Passage%25201.jpg": "5bac8ea2ea1f67d793ec9fdd61e1c1d2",
"assets/assets/images/PZED%2520logo.png": "c5cc336c13ea7f1ab040ea0f0133fca4",
"assets/assets/images/Reception/Reception%25201.JPG": "ad04b09bd3882fc3ee48a6e76a8ec14b",
"assets/assets/images/Reception/Reception%25202.png": "57010bedc9e80c688a2b0c3dc5a0b2f8",
"assets/assets/images/Reception/Reception%25203.jpg": "eb120a7cb80fd462c0759adf11e8dcd1",
"assets/assets/images/Reception/Reception%25204.jpg": "5856604adf432419d6fa5620590d23bb",
"assets/assets/images/Restaurant/Restaurant%25201.jpg": "519bee4a310f938336f93d41e55d420f",
"assets/assets/images/Standard%2520Room/Standard%25201.png": "4972e578516226e5e1d55ec8bedd7c89",
"assets/assets/images/Standard%2520Room/Standard%25202.JPG": "c17f21750ecb5f228458bad8d2e165af",
"assets/assets/images/Standard%2520Room/Standard%25203.jpg": "b544918a4a2aa06840ea265b08f82575",
"assets/assets/images/Standard%2520Room/Standard%25204.JPG": "322f665d06ee5c3fbaf9f05149a1f283",
"assets/assets/images/VIP%2520Bar/VIP%2520Bar%25201.JPG": "cea443194f475e8d110d394006681114",
"assets/assets/images/VIP%2520Bar/VIP%2520Bar%25202.JPG": "e4c21e6244c3cfb6d67fb1938498dad8",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "205043bfc43d4c2ed0c59935e01ab146",
"assets/NOTICES": "df515fa88e8bda44677ccb578919c0ae",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "d7d83bd9ee909f8a9b348f56ca7b68c6",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "2182952e4eeb23f99c0573d8d3b28934",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "c46f9ac669fdcafb49293c2d1b38c753",
"/": "c46f9ac669fdcafb49293c2d1b38c753",
"main.dart.js": "26a15cbf5b3416030c738d3b5b61d65c",
"manifest.json": "ec64bfa9f89f9583fc3b25577c555433",
"version.json": "40a1b7d2b934c934f46f8a3f91cb68ca"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}

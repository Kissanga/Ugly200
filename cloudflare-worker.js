export default {
  async fetch(request, env) {
    // Always allow CORS preflight (no password check on OPTIONS)
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization,Content-Type,Notion-Version,X-App-Password',
        }
      });
    }

    // ── App password gate ─────────────────────────────────────────
    const appPw = request.headers.get('X-App-Password') || '';
    if (appPw !== env.APP_PASSWORD) {
      return new Response('Unauthorized', {
        status: 401,
        headers: { 'Access-Control-Allow-Origin': '*' }
      });
    }

    const url = new URL(request.url);
    const pathname = url.pathname;

    // What goes on to Notion and Groq: never the app password, nor the browser's cookies, origin and referrer
    // (they reached both services and their logs). A response passed on says so in X-Upstream, so the app can tell
    // a refused server key from a wrong app password.
    const upstreamHeaders = () => {
      const h = new Headers(request.headers);
      ['X-App-Password', 'Cookie', 'Origin', 'Referer'].forEach(k => h.delete(k));
      return h;
    };
    const passBack = (response, who) => {
      const r = new Response(response.body, response);
      r.headers.set('Access-Control-Allow-Origin', '*');
      r.headers.set('X-Upstream', who);
      r.headers.set('Access-Control-Expose-Headers', 'X-Upstream');
      return r;
    };

    // Ping route — just confirms the password is correct
    if (pathname === '/ping') {
      return new Response('{"ok":true}', {
        headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
      });
    }

    // Route to Notion API
    if (pathname.startsWith('/v1/')) {
      const notionUrl = 'https://api.notion.com' + pathname + url.search;
      const headers = upstreamHeaders();

      // Inject Notion token from environment (not from frontend)
      headers.set('Authorization', `Bearer ${env.NOTION_TOKEN}`);
      headers.set('Notion-Version', '2022-06-28');

      const response = await fetch(notionUrl, {
        method: request.method,
        headers: headers,
        body: request.method !== 'GET' ? request.body : undefined,
      });

      return passBack(response, 'Notion');
    }

    // Route to Groq API
    if (pathname.startsWith('/groq/')) {
      const groqPath = pathname.replace('/groq/', '');
      const groqUrl = 'https://api.groq.com/' + groqPath + url.search;
      const headers = upstreamHeaders();

      // Inject Groq key from environment
      headers.set('Authorization', `Bearer ${env.GROQ_KEY}`);

      const response = await fetch(groqUrl, {
        method: request.method,
        headers: headers,
        body: request.method !== 'GET' ? request.body : undefined,
      });

      return passBack(response, 'Groq');
    }

    return new Response('Not found', { status: 404 });
  }
};

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization,Content-Type,Notion-Version',
        }
      });
    }

    const url = new URL(request.url);
    const pathname = url.pathname;

    // Route to Notion API
    if (pathname.startsWith('/v1/')) {
      const notionUrl = 'https://api.notion.com' + pathname + url.search;
      const headers = new Headers(request.headers);

      // Inject Notion token from environment (not from frontend)
      headers.set('Authorization', `Bearer ${env.NOTION_TOKEN}`);
      headers.set('Notion-Version', '2022-06-28');

      const response = await fetch(notionUrl, {
        method: request.method,
        headers: headers,
        body: request.method !== 'GET' ? request.body : undefined,
      });

      const newResponse = new Response(response.body, response);
      newResponse.headers.set('Access-Control-Allow-Origin', '*');
      return newResponse;
    }

    // Route to Groq API
    if (pathname.startsWith('/groq/')) {
      const groqPath = pathname.replace('/groq/', '');
      const groqUrl = 'https://api.groq.com/' + groqPath + url.search;
      const headers = new Headers(request.headers);

      // Inject Groq key from environment
      headers.set('Authorization', `Bearer ${env.GROQ_KEY}`);

      const response = await fetch(groqUrl, {
        method: request.method,
        headers: headers,
        body: request.method !== 'GET' ? request.body : undefined,
      });

      const newResponse = new Response(response.body, response);
      newResponse.headers.set('Access-Control-Allow-Origin', '*');
      return newResponse;
    }

    return new Response('Not found', { status: 404 });
  }
};

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type EmailRequest = {
  to: { email: string; name?: string }[];
  subject: string;
  html?: string;
  text?: string;
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const brevoApiKey = Deno.env.get("BREVO_API_KEY");
  const senderEmail = Deno.env.get("BREVO_SENDER_EMAIL");
  const senderName = Deno.env.get("BREVO_SENDER_NAME") ?? "P-ZED Homes";

  if (!brevoApiKey || !senderEmail) {
    return new Response(
      JSON.stringify({ error: "Missing Brevo configuration" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const body = (await req.json().catch(() => null)) as EmailRequest | null;
  if (!body?.to?.length || !body.subject || (!body.html && !body.text)) {
    return new Response(
      JSON.stringify({ error: "Missing required fields" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const brevoResponse = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "api-key": brevoApiKey,
    },
    body: JSON.stringify({
      sender: { email: senderEmail, name: senderName },
      to: body.to,
      subject: body.subject,
      htmlContent: body.html,
      textContent: body.text,
    }),
  });

  if (!brevoResponse.ok) {
    const errText = await brevoResponse.text();
    return new Response(
      JSON.stringify({ error: "Brevo send failed", details: errText }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

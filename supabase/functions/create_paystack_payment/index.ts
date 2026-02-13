import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type CreatePaymentRequest = {
  amount_in_kobo: number;
  email: string;
  reference: string;
  metadata?: Record<string, unknown>;
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const paystackSecret = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!paystackSecret || paystackSecret.trim() === "") {
    return new Response(
      JSON.stringify({
        error: "Paystack is not configured. Set PAYSTACK_SECRET_KEY in Supabase Edge Function secrets.",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const body = (await req.json().catch(() => null)) as CreatePaymentRequest | null;
  if (
    !body?.amount_in_kobo ||
    !body?.email ||
    !body?.reference
  ) {
    return new Response(
      JSON.stringify({ error: "Missing required fields: amount_in_kobo, email, reference" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    // Paystack Transaction Initialize - standard one-time payment flow
    const paystackRes = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${paystackSecret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: body.amount_in_kobo,
        email: body.email,
        reference: body.reference,
        currency: "NGN",
        metadata: {
          booking_reference: body.reference,
          ...(body.metadata || {}),
        },
      }),
    });

    const paystackJson = await paystackRes.json();

    if (!paystackRes.ok) {
      return new Response(
        JSON.stringify({
          error: paystackJson?.message || "Paystack API error",
          details: paystackJson,
        }),
        { status: paystackRes.status, headers: { "Content-Type": "application/json" } },
      );
    }

    const authUrl = paystackJson?.data?.authorization_url;
    if (!authUrl || typeof authUrl !== "string") {
      return new Response(
        JSON.stringify({ error: "Paystack did not return a payment URL" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ link: authUrl }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "Failed to create payment link", details: String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type VerifyRequest = {
  booking_id: string;
  payment_reference: string;
  guest_email: string;
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const paystackSecret = Deno.env.get("PAYSTACK_SECRET_KEY");

  if (!supabaseUrl || !serviceRoleKey || !paystackSecret) {
    return new Response(
      JSON.stringify({ error: "Missing server configuration" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const body = (await req.json().catch(() => null)) as VerifyRequest | null;
  if (!body?.booking_id || !body?.payment_reference || !body?.guest_email) {
    return new Response(
      JSON.stringify({ error: "Missing required fields" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Verify Paystack transaction
  const paystackRes = await fetch(
    `https://api.paystack.co/transaction/verify/${body.payment_reference}`,
    {
      headers: {
        Authorization: `Bearer ${paystackSecret}`,
        "Content-Type": "application/json",
      },
    },
  );

  if (!paystackRes.ok) {
    return new Response(
      JSON.stringify({ error: "Payment verification failed" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const paystackJson = await paystackRes.json();
  if (!paystackJson?.data?.status || paystackJson.data.status !== "success") {
    return new Response(
      JSON.stringify({ error: "Payment not successful" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const amount = Number(paystackJson.data.amount || 0);
  const email = String(paystackJson.data.customer?.email || "").toLowerCase();

  // Fetch booking to validate amount + email + reference
  const { data: booking, error: bookingError } = await supabase
    .from("bookings")
    .select("id,total_amount,guest_email,payment_reference")
    .eq("id", body.booking_id)
    .single();

  if (bookingError || !booking) {
    return new Response(
      JSON.stringify({ error: "Booking not found" }),
      { status: 404, headers: { "Content-Type": "application/json" } },
    );
  }

  if (
    booking.payment_reference !== body.payment_reference ||
    String(booking.guest_email || "").toLowerCase() !==
      body.guest_email.toLowerCase()
  ) {
    return new Response(
      JSON.stringify({ error: "Booking details mismatch" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  if (Number(booking.total_amount || 0) !== amount || email !== body.guest_email.toLowerCase()) {
    return new Response(
      JSON.stringify({ error: "Payment details mismatch" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  // Confirm booking (writes income record + marks payment verified)
  const { error: confirmError } = await supabase.rpc("confirm_guest_booking", {
    p_booking_id: body.booking_id,
    p_paid_amount: amount,
    p_payment_reference: body.payment_reference,
    p_payment_method: "online",
    p_guest_email: body.guest_email,
  });

  if (confirmError) {
    return new Response(
      JSON.stringify({ error: "Failed to confirm booking" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

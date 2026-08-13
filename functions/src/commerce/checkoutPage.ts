import { db, functions } from "../config/main";
import { commerceApiUrls } from "./payment";
import { commercePaymentsEnabled } from "./readiness";
import { ensureMerchantOrderingLink } from "../ecommerce/getMerchantOrderingLink";

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .split("&")
    .join("&amp;")
    .split("<")
    .join("&lt;")
    .split(">")
    .join("&gt;")
    .split('"')
    .join("&quot;")
    .split("'")
    .join("&#039;");
}

function safeJson(value: unknown): string {
  return JSON.stringify(value).replace(/</g, "\\u003c");
}

function pageShell(title: string, content: string, script = ""): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="theme-color" content="#106C55">
  <title>${escapeHtml(title)}</title>
  <style>
    :root{color-scheme:light;--green:#106c55;--ink:#14231f;--muted:#5c6d67;--line:#dce5e1;--paper:#fbfaf6;--danger:#a12727}
    *{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
    header{background:var(--green);color:#fff;padding:18px 20px;font-weight:800;font-size:20px;letter-spacing:-.3px}.wrap{width:min(720px,100%);margin:0 auto;padding:20px 16px 48px}
    .card{background:#fff;border:1px solid var(--line);border-radius:20px;padding:18px;box-shadow:0 8px 30px rgba(20,35,31,.06);margin-bottom:16px}.product{display:grid;grid-template-columns:96px 1fr;gap:16px;align-items:center}
    .product img{width:96px;height:96px;object-fit:cover;border-radius:14px;background:#eef2f0}.eyebrow{color:var(--green);font-size:12px;font-weight:800;text-transform:uppercase;letter-spacing:.08em}.title{font-size:22px;line-height:1.15;margin:5px 0 8px}.price{font-size:23px;font-weight:850}.muted{color:var(--muted);line-height:1.5}.grid{display:grid;grid-template-columns:1fr 1fr;gap:14px}.wide{grid-column:1/-1}
    label{display:block;font-size:13px;font-weight:750;margin-bottom:6px}input{width:100%;border:1px solid #b9c8c2;border-radius:12px;padding:13px 12px;font:inherit;outline:none}input:focus{border-color:var(--green);box-shadow:0 0 0 3px rgba(16,108,85,.12)}input[type=radio]{width:auto;accent-color:var(--green)}
    button{width:100%;border:0;border-radius:13px;background:var(--green);color:#fff;font:inherit;font-weight:800;padding:15px;cursor:pointer}button:disabled{opacity:.6;cursor:wait}.secure{text-align:center;color:var(--muted);font-size:12px;margin-top:10px}.error{display:none;background:#fff0f0;border:1px solid #efb9b9;color:var(--danger);border-radius:12px;padding:12px;margin-bottom:14px}.status{text-align:center;padding:28px 18px}.status .icon{width:68px;height:68px;border-radius:50%;background:#e4f3ed;color:var(--green);display:grid;place-items:center;font-size:34px;margin:0 auto 16px}.ref{font-family:ui-monospace,monospace;background:#eef2f0;border-radius:8px;padding:4px 8px}.product-details{margin-top:12px;border-top:1px solid var(--line);padding-top:12px}.product-details summary{color:var(--green);font-weight:800;cursor:pointer}.product-details p{margin-bottom:0}
    .quote{display:none;border:1px solid #b8d7cb;background:#f2faf7;border-radius:14px;padding:14px;margin:16px 0}.quote-total{font-size:22px;font-weight:850;margin:4px 0}.channels{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px}.channel{display:flex;gap:8px;align-items:center;border:1px solid #b9c8c2;background:#fff;border-radius:11px;padding:11px}.channel label{margin:0;cursor:pointer}
    @media(max-width:560px){.grid{grid-template-columns:1fr}.wide{grid-column:auto}.product{grid-template-columns:78px 1fr}.product img{width:78px;height:78px}.title{font-size:19px}}
  </style>
</head>
<body><header>Spaza One</header><main class="wrap">${content}</main>${script}</body>
</html>`;
}

function statusPage(input: {
  listingId: string;
  orderId: string;
  token: string;
}): string {
  const config = safeJson({
    orderId: input.orderId,
    token: input.token,
    statusUrl: commerceApiUrls.orderStatus,
  });
  const content = `<section class="card status">
    <div class="icon">✓</div>
    <div class="eyebrow">Order received</div>
    <h1>Thank you for your order request</h1>
    <p class="muted" id="statusText">Spaza One is checking the latest order status.</p>
    <p>Order <span class="ref">${escapeHtml(input.orderId.slice(0, 8).toUpperCase())}</span></p>
  </section>`;
  const script = `<script>
    const config=${config};
    const statusText=document.getElementById('statusText');
    let checks=0;
    async function check(){
      checks++;
      try{
        const url=new URL(config.statusUrl);
        url.searchParams.set('order',config.orderId);
        url.searchParams.set('token',config.token);
        const response=await fetch(url);
        const result=await response.json();
        if(response.ok&&result.paymentMethod==='manual'&&result.paymentStatus==='awaiting_manual_confirmation'){
          statusText.textContent='Your request was sent to the seller. They will contact you to arrange payment and confirm the order.';
          return;
        }
        if(response.ok&&result.paymentStatus==='paid'){
          statusText.textContent='Payment confirmed. Your order is now in the Spaza One fulfilment queue.';
          return;
        }
        if(response.ok&&['cancelled','refunded'].includes(result.status)){
          statusText.textContent='This order is '+result.status+'. Please contact the seller if you need help.';
          return;
        }
      }catch(_){/* keep polling */}
      if(checks<20)setTimeout(check,3000);
      else statusText.textContent='Confirmation is taking longer than usual. Keep this page or check with the seller using your order reference.';
    }
    check();
  </script>`;
  return pageShell("Spaza One order", content, script);
}

function checkoutUnavailablePage(orderingUrl = ""): string {
  const action = orderingUrl
    ? `<p><a href="${escapeHtml(orderingUrl)}" style="display:block;border-radius:13px;background:#106c55;color:#fff;text-decoration:none;font-weight:800;padding:15px">Continue on WhatsApp</a></p>`
    : "";
  return pageShell(
    "Order on WhatsApp · Spaza One",
    `<section class="card status">
      <div class="icon">💬</div>
      <div class="eyebrow">Spaza One</div>
      <h1>Order through WhatsApp</h1>
      <p class="muted">This shop currently takes orders through its Spaza One WhatsApp ordering link.</p>
      ${action}
    </section>`,
  );
}

export function checkoutPage(input: {
  listingId: string;
  title: string;
  description: string;
  image: string;
  sellPriceMinor: number;
  shippingNotes: string;
  digitalPaymentsEnabled: boolean;
}): string {
  const config = safeJson({
    listingId: input.listingId,
    createUrl: commerceApiUrls.createOrder,
    prepareUrl: commerceApiUrls.preparePublicCheckout,
  });
  const image = input.image
    ? `<img src="${escapeHtml(input.image)}" alt="${escapeHtml(input.title)}">`
    : `<div style="width:96px;height:96px;border-radius:14px;background:#eef2f0;display:grid;place-items:center;font-size:34px">🛍️</div>`;
  const shipping = input.shippingNotes
    ? `<p class="muted"><strong>Delivery:</strong> ${escapeHtml(input.shippingNotes)}</p>`
    : "";
  const details = input.description
    ? `<details class="product-details"><summary>View product details</summary><p class="muted">${escapeHtml(input.description)}</p></details>`
    : "";
  const emailRequired = input.digitalPaymentsEnabled ? "required" : "";
  const emailLabel = input.digitalPaymentsEnabled
    ? "Email for payment receipt"
    : "Email (optional)";
  const actionLabel = input.digitalPaymentsEnabled
    ? "Calculate delivery & pay securely"
    : "Calculate delivery & send order request";
  const paymentNotice = input.digitalPaymentsEnabled
    ? "Spaza One verifies live supplier and delivery pricing. Card details are entered only on Paystack."
    : "No online payment is collected. The seller will contact you to arrange payment and confirm your order.";
  const content = `<section class="card product">${image}<div>
      <div class="eyebrow">Spaza One supplier product</div>
      <h1 class="title">${escapeHtml(input.title)}</h1>
      <div class="price">From R ${(input.sellPriceMinor / 100).toFixed(2)}</div>
      <div class="muted">Final delivery price is calculated from your address.</div>
    </div></section>
    <section class="card">${shipping}${details}</section>
    <section class="card">
      <h2>Delivery details</h2>
      <div class="error" id="error"></div>
      <form id="checkoutForm">
        <div class="grid">
          <div><label for="name">Full name</label><input id="name" autocomplete="name" required maxlength="100"></div>
          <div><label for="phone">Mobile number</label><input id="phone" autocomplete="tel" inputmode="tel" required maxlength="32"></div>
          <div><label for="quantity">Quantity</label><input id="quantity" type="number" inputmode="numeric" min="1" max="20" value="1" required></div>
          <div class="wide"><label for="email">${emailLabel}</label><input id="email" type="email" autocomplete="email" ${emailRequired} maxlength="160"></div>
          <div class="wide"><label for="line1">Street address</label><input id="line1" autocomplete="address-line1" required maxlength="160"></div>
          <div class="wide"><label for="line2">Complex, unit or building (optional)</label><input id="line2" autocomplete="address-line2" maxlength="160"></div>
          <div><label for="suburb">Suburb</label><input id="suburb" required maxlength="100"></div>
          <div><label for="city">City / town</label><input id="city" autocomplete="address-level2" required maxlength="100"></div>
          <div><label for="province">Province</label><input id="province" autocomplete="address-level1" required maxlength="100"></div>
          <div><label for="postalCode">Postal code</label><input id="postalCode" autocomplete="postal-code" inputmode="numeric" required maxlength="12"></div>
          <div class="wide"><section class="quote" id="quote"><div class="eyebrow">Verified checkout total</div><div class="quote-total" id="quoteTotal"></div><div class="muted" id="quoteDelivery"></div><div class="channels" id="channels"></div></section><button id="payButton" type="submit">${actionLabel}</button><div class="secure">${paymentNotice}</div></div>
        </div>
      </form>
    </section>`;
  const script = `<script>
    const config=${config};
    const form=document.getElementById('checkoutForm');
    const button=document.getElementById('payButton');
    const errorBox=document.getElementById('error');
    const quoteBox=document.getElementById('quote');
    const quoteTotal=document.getElementById('quoteTotal');
    const quoteDelivery=document.getElementById('quoteDelivery');
    const channels=document.getElementById('channels');
    const value=id=>document.getElementById(id).value.trim();
    const attempt=(crypto.randomUUID?crypto.randomUUID():Date.now()+'-'+Math.random());
    const channelLabels={card:'Card',eft:'Instant EFT',capitec_pay:'Capitec Pay',qr:'Scan to Pay'};
    let quoted=null;
    const deliveryAddress=()=>({line1:value('line1'),line2:value('line2'),suburb:value('suburb'),city:value('city'),province:value('province'),postalCode:value('postalCode'),country:'ZA'});
    const resetQuote=()=>{quoted=null;quoteBox.style.display='none';channels.replaceChildren();button.textContent=${safeJson(actionLabel)};};
    form.addEventListener('input',event=>{if(quoted&&event.target.name!=='paymentChannel')resetQuote();});
    form.addEventListener('submit',async event=>{
      event.preventDefault();button.disabled=true;button.textContent='Checking live delivery price…';errorBox.style.display='none';
      try{
        const quantity=Number(value('quantity'));
        if(!quoted){
          const response=await fetch(config.prepareUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({listingId:config.listingId,quantity,deliveryAddress:deliveryAddress()})});
          const result=await response.json();
          if(!response.ok||result.status!=='ready')throw new Error(result.reason==='quantity_unavailable'?'That quantity is not available right now.':result.reason==='payment_unavailable'?'No secure payment method leaves enough margin for this order.':'Live delivery pricing is unavailable right now.');
          if(!Array.isArray(result.paymentOptions)||result.paymentOptions.length===0)throw new Error('No secure payment method is available for this order.');
          quoted=result;
          document.getElementById('quantity').max=String(result.maxQuantity||20);
          quoteTotal.textContent='R '+(Number(result.amountDueMinor)/100).toFixed(2);
          quoteDelivery.textContent='Estimated delivery '+result.deliveryEstimate.minDays+'–'+result.deliveryEstimate.maxDays+' days. Choose how to pay:';
          channels.replaceChildren(...result.paymentOptions.map((channel,index)=>{const row=document.createElement('div');row.className='channel';const radio=document.createElement('input');radio.type='radio';radio.name='paymentChannel';radio.id='channel-'+channel;radio.value=channel;radio.required=true;radio.checked=index===0;const label=document.createElement('label');label.htmlFor=radio.id;label.textContent=channelLabels[channel]||channel;row.append(radio,label);return row;}));
          quoteBox.style.display='block';
          button.disabled=false;button.textContent='Pay R '+(Number(result.amountDueMinor)/100).toFixed(2)+' securely';quoteBox.scrollIntoView({behavior:'smooth',block:'center'});return;
        }
        const paymentChannel=form.querySelector('input[name=paymentChannel]:checked')?.value;
        if(!paymentChannel||!quoted.paymentOptions.includes(paymentChannel))throw new Error('Choose a secure payment method.');
        button.textContent='Opening secure payment…';
        const body={listingId:config.listingId,checkoutAttemptId:attempt,buyer:{name:value('name'),email:value('email'),phone:value('phone')},deliveryAddress:deliveryAddress(),quantity,paymentChannel};
        const response=await fetch(config.createUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
        const result=await response.json();
        if(!response.ok)throw new Error(result.error||'Order could not be submitted.');
        const next=result.authorizationUrl||result.confirmationUrl;
        if(!next)throw new Error('Order could not be submitted.');
        window.location.assign(next);
      }catch(error){errorBox.textContent=error.message||'Order could not be submitted.';errorBox.style.display='block';button.disabled=false;button.textContent=quoted?'Pay securely':${safeJson(actionLabel)};errorBox.scrollIntoView({behavior:'smooth',block:'center'});}
    });
  </script>`;
  return pageShell(`${input.title} · Spaza One`, content, script);
}

/** Public mobile checkout page shared by sellers through WhatsApp. */
export const commerceCheckout = functions.https.onRequest(async (req, res) => {
  res.set("Content-Type", "text/html; charset=utf-8");
  res.set("Cache-Control", "no-store");
  res.set(
    "Content-Security-Policy",
    "default-src 'self'; img-src https: data:; style-src 'unsafe-inline'; " +
      "script-src 'unsafe-inline'; connect-src https: http://127.0.0.1:*",
  );
  if (req.method !== "GET") {
    res.status(405).send(pageShell("Spaza One", "<h1>Method not allowed</h1>"));
    return;
  }
  const listingId = String(req.query.listing ?? "").trim();
  const orderId = String(req.query.order ?? "").trim();
  const token = String(req.query.token ?? "").trim();
  if (orderId && token && listingId) {
    res.status(200).send(statusPage({ listingId, orderId, token }));
    return;
  }
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(listingId)) {
    res
      .status(404)
      .send(
        pageShell(
          "Product unavailable · Spaza One",
          '<section class="card status"><h1>Product unavailable</h1><p class="muted">This Spaza One checkout link is not valid.</p></section>',
        ),
      );
    return;
  }
  const listing = await db.doc(`commerceListings/${listingId}`).get();
  const data = listing.data() ?? {};
  if (!listing.exists || data.active !== true) {
    res
      .status(404)
      .send(
        pageShell(
          "Product unavailable · Spaza One",
          '<section class="card status"><h1>Product unavailable</h1><p class="muted">The seller is not offering this item right now.</p></section>',
        ),
      );
    return;
  }
  if (!commercePaymentsEnabled()) {
    try {
      const ordering = await ensureMerchantOrderingLink(
        String(data.sellerId ?? ""),
      );
      const url = new URL(ordering.orderingUrl);
      url.searchParams.set(
        "text",
        `shop ${ordering.code}\nproduct ${listingId}`,
      );
      res.redirect(302, url.toString());
    } catch (error) {
      console.error("commerceCheckout WhatsApp redirect failed", {
        message: error instanceof Error ? error.message : "error",
      });
      res.status(200).send(checkoutUnavailablePage());
    }
    return;
  }
  const images = Array.isArray(data.images) ? data.images : [];
  res.status(200).send(
    checkoutPage({
      listingId,
      title: String(data.title ?? "Product"),
      description: String(data.description ?? ""),
      image: String(images[0] ?? ""),
      sellPriceMinor: Number(data.sellPriceMinor ?? 0),
      shippingNotes: String(data.shippingNotes ?? ""),
      digitalPaymentsEnabled: commercePaymentsEnabled(),
    }),
  );
});

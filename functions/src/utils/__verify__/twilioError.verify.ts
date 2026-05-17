// functions/src/utils/__verify__/twilioError.verify.ts
//
// PAS-WA-01 manual verification harness. Not wired into a test runner
// (the functions package has no test infra today); intended to be
// executed with `npx ts-node` or compiled via `tsc` and run with
// `node`. Confirms that the normalizer covers:
//   1) full-detail Twilio RestException
//   2) AxiosError-shaped error from the Content REST path
//   3) bare Error with no code/message (forces the Pasella fallback)
//
// Run:
//   cd functions
//   ./node_modules/.bin/tsc --noEmit src/utils/__verify__/twilioError.verify.ts
//   # or: npx ts-node src/utils/__verify__/twilioError.verify.ts

import { normalizeTwilioError } from "../twilioError";

const cases: Array<{ label: string; err: unknown; channel: "whatsapp" | "sms" }> = [
  {
    label: "Twilio RestException (full detail)",
    channel: "whatsapp",
    err: Object.assign(new Error("Template paused due to low quality"), {
      code: 63016,
      status: 400,
      moreInfo: "https://www.twilio.com/docs/errors/63016",
    }),
  },
  {
    label: "AxiosError-shaped REST failure",
    channel: "whatsapp",
    err: {
      message: "Request failed with status code 400",
      response: {
        status: 400,
        data: {
          code: 21610,
          message: "The message To phone number has been blacklisted",
          more_info: "https://www.twilio.com/docs/errors/21610",
        },
      },
    },
  },
  {
    label: "Bare Error (no provider detail — must use Pasella fallback)",
    channel: "sms",
    err: new Error(""),
  },
  {
    label: "Network-style undefined error",
    channel: "whatsapp",
    err: undefined,
  },
];

for (const c of cases) {
  const norm = normalizeTwilioError(c.err, c.channel);
  // eslint-disable-next-line no-console
  console.log(`\n=== ${c.label} ===`);
  // eslint-disable-next-line no-console
  console.log(JSON.stringify(norm, null, 2));
  if (!norm.pasellaMessage) {
    throw new Error(`Missing pasellaMessage for case: ${c.label}`);
  }
}

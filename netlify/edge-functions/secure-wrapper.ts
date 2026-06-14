import type { Context } from "@netlify/edge-functions";

export default async (request: Request, context: Context) => {
  // استخراج التوكن الذي تم حقنه عبر الغلاف
  const token = context.cookies.get("Edge-Auth-Token");
  const expectedToken = Netlify.env.get("APP_SECRET_TOKEN");

  // الحظر الفوري لأي متصفح عادي أو محاولة خارجية
  if (!token || token !== expectedToken) {
    console.log("❌ تم حظر محاولة اختراق أو وصول خارجي.");
    return new Response(
      JSON.stringify({
        error: "Access Denied",
        message: "Secured by Native Wrapper Environment."
      }), 
      {
        status: 403,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store"
        }
      }
    );
  }

  // السماح بمرور الطلب لتحميل ملفات التطبيق (Wasm)
  return context.next();
};

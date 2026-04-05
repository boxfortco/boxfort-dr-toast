import type { Metadata } from "next";
import { DM_Sans, Fraunces } from "next/font/google";
import "./globals.css";

const sans = DM_Sans({
  variable: "--font-boxfort-sans",
  subsets: ["latin"],
});

const display = Fraunces({
  variable: "--font-boxfort-display",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "BoxFort — Dr. Toast's Mix-Up",
  description:
    "Join a BoxFort room on your phone. The host runs the game on the big screen.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${sans.variable} ${display.variable} min-h-screen bg-[#f4efe6] font-sans antialiased`}
      >
        {children}
      </body>
    </html>
  );
}

import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/react";
import { DM_Sans, Fraunces } from "next/font/google";
import "./globals.css";

const siteUrl = "https://detectivetoast.com";

const sans = DM_Sans({
  variable: "--font-boxfort-sans",
  subsets: ["latin"],
});

const display = Fraunces({
  variable: "--font-boxfort-display",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  icons: {
    icon: [{ url: "/characters/appIcon.png", type: "image/png" }],
    apple: "/characters/appIcon.png",
  },
  title: "Detective Toast: Hunt for the Burnt Toast",
  description:
    "Join a room on your phone — family party mystery: clues, bluffs, and a vote. The host runs the game on the big screen.",
  openGraph: {
    title: "Detective Toast: Hunt for the Burnt Toast",
    description:
      "Join a room on your phone. Detective Toasts share a secret; Burnt Toast does not. Clues, vote, showdown.",
    url: siteUrl,
    siteName: "Detective Toast",
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Detective Toast: Hunt for the Burnt Toast",
    description:
      "Family party mystery on your phones. Enter the room code from the hub and play your slice.",
  },
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
        <Analytics />
      </body>
    </html>
  );
}

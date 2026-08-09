#!/bin/bash
git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
export PATH="$PATH:`pwd`/_flutter/bin"
echo "SUPABASE_URL=$SUPABASE_URL" > .env
echo "SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" >> .env
flutter config --enable-web
flutter build web --release
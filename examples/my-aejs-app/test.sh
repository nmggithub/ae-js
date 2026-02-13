# Kill all instances of my-aejs-app
killall -9 my-aejs-app

# Clear the output files
rm -f app_out app_err

# Clean the project
npm run clean
rm -rf node_modules package-lock.json

# build the dependencies
npm --prefix ../../ run build --workspaces

# Pack the tarballs
npm run pack-tarballs

# Install the tarballs
npm install

# Build the app
npm run build

# Package the app
npm run package

# Sign the app
codesign --force --deep --sign "$CODE_SIGN_IDENTITY" \
    ./out/my-aejs-app-darwin-arm64/my-aejs-app.app

# Run the app
open ./out/my-aejs-app-darwin-arm64/my-aejs-app.app \
    --stdout app_out --stderr app_err

# Wait for the app to start
sleep 3

# Send an Apple event to the app
osascript -e 'tell application "my-aejs-app" to doThing'

# Check that the output matches the expected output
if ! grep -q "Received Apple event:" app_out; then
    echo "Error: Apple event not received"
    exit 1
fi

sleep 3

# ensure the app is still running
if ! pgrep -f "my-aejs-app" > /dev/null; then
    echo "Error: my-aejs-app is not running"
    exit 1
fi

# clean the output
echo "" > app_out

# Send another Apple event to the app
osascript -e 'tell application "my-aejs-app" to doThing'

# Check that the event was not handled
if grep -q "Received Apple event:" app_out; then
    echo "Error: Apple event was handled"
    exit 1
fi

# Test passed
echo "Test passed"

# Kill the app
killall -9 my-aejs-app

# Clean up
rm -f app_out app_err
rm -rf out
npm run clean
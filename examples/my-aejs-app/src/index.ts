import { app, BrowserWindow } from 'electron';
import path from 'node:path';

import {
    handleJSAppleEvent,
    unhandleJSAppleEvent,
    AEJSDataDescriptor,
    AEJSNullDescriptor
} from '@ae-js/bridge';

import {
    AEDataDescriptor
} from '@ae-js/bridge/native';

handleJSAppleEvent(
    'aejs',
    'DOTH',
    (event, replyExpected) => {
        console.log('Received Apple event:', event);
        setTimeout(() => {
            unhandleJSAppleEvent('aejs', 'DOTH'); // only handle one event
        }, 0); // We use setTimeout as to not unhandle *while* executing the handler
        if (replyExpected) {
            return {};
        } else return null;
    }
);

handleJSAppleEvent(
    'aejs',
    'PING',
    (event, replyExpected) => {
        console.log('Received PING event:', event);
        let incomingDirectParameter = '----' in event.parameters
            && !(event.parameters['----'] instanceof AEJSNullDescriptor)
            ? event.parameters['----']
            : null;
        console.log(event.parameters);
        if (replyExpected) {
            const parsedIncomingDirectParameter: string = (() => {
                if (incomingDirectParameter) {
                    console.log('incomingDirectParameter:', incomingDirectParameter);
                    console.log('incomingDirectParameter type:', incomingDirectParameter.descriptorType);
                    try {
                        return incomingDirectParameter?.toString()
                            ?? "Could not parse incoming direct parameter";
                    } catch (error) {
                        console.error('Error parsing incoming direct parameter:', error);
                    }
                }
                return "No direct parameter";
            })();
            return {
                '----': new AEJSDataDescriptor(
                    new AEDataDescriptor(
                        'utf8',
                        new TextEncoder().encode(`Pong! ${parsedIncomingDirectParameter}`)
                    )
                )
            };
        }
        return null;
    }
);

handleJSAppleEvent(
    'aejs',
    'ERR1',
    (event, replyExpected) => {
        throw new Error('What did you expect?');
    }
);

handleJSAppleEvent(
    'aejs',
    'ERR2',
    async (event, replyExpected) => {
        await new Promise(resolve => setTimeout(resolve, 7000));
        throw new Error('What did you expect?');
    }
);

const createWindow = () => {
    // Create the browser window.
    const mainWindow = new BrowserWindow({
        width: 800,
        height: 600,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
        },
    });

    // and load the index.html of the app.
    // mainWindow.loadFile(path.join(__dirname, 'index.html'));

    // Open the DevTools.
    mainWindow.webContents.openDevTools();
};

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.
app.whenReady().then(() => {
    createWindow();

    // On OS X it's common to re-create a window in the app when the
    // dock icon is clicked and there are no other windows open.
    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) {
            createWindow();
        }
    });
});

// Quit when all windows are closed, except on macOS. There, it's common
// for applications and their menu bar to stay active until the user quits
// explicitly with Cmd + Q.
app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
        app.quit();
    }
});

// In this file you can include the rest of your app's specific main process
// code. You can also put them in separate files and import them here.

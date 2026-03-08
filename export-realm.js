import Realm from 'realm';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createObjectCsvWriter } from 'csv-writer';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// 取得命令行參數
const args = process.argv.slice(2);
const format = args.includes('--format') ? args[args.indexOf('--format') + 1] : 'json';
const customPath = args.includes('--path') ? args[args.indexOf('--path') + 1] : null;

async function exportRealmData() {
  try {
    // 設置 Realm 數據庫路徑
    let realmPath = customPath;
    
    if (!realmPath) {
      // 尋找預設位置
      const possiblePaths = [
        path.join(process.env.APPDATA || '', 'osu', 'client.realm'),
        path.join(process.env.USERPROFILE || '', 'AppData', 'Roaming', 'osu', 'client.realm'),
        'D:\\osu!lazer\\client.realm',
        'C:\\osu!lazer\\client.realm'
      ];
      
      for (const p of possiblePaths) {
        if (fs.existsSync(p)) {
          realmPath = p;
          break;
        }
      }
    }

    if (!realmPath) {
      console.warn(`⚠️ 找不到 Realm 文件`);
      console.log(`請手動指定路徑：node export-realm.js --path "路徑/到/client.realm"`);
      return;
    }

    console.log(`🔍 尋找 Realm DB: ${realmPath}`);

    // 檢查文件是否存在
    if (!fs.existsSync(realmPath)) {
      console.warn(`❌ 找不到 Realm 文件於 ${realmPath}`);
      return;
    }

    // 打開 Realm 數據庫（不指定 schema，讀取現有的 schema）
    const realm = await Realm.open({
      path: realmPath,
      readOnly: true,
      schemaless: true
    });

    console.log('✅ 成功連接到 Realm 數據庫\n');

    // 獲取所有物件的類型
    const objectSchemas = realm.schema.map(s => s.name);
    console.log(`📊 找到的物件類型: ${objectSchemas.join(', ')}\n`);

    const data = {
      exportTime: new Date().toISOString(),
      objects: {},
      summary: {
        totalObjects: 0,
        types: objectSchemas
      }
    };

    // 迭代所有物件類型並匯出
    for (const objectType of objectSchemas) {
      try {
        const objects = realm.objects(objectType);
        const objectArray = Array.from(objects);
        
        if (objectArray.length === 0) {
          console.log(`⊘ ${objectType}: 沒有數據`);
          continue;
        }
        
        // 轉換物件，使用改進的錯誤處理
        const convertedArray = objectArray.map((obj, index) => {
          try {
            return convertObject(obj);
          } catch (e) {
            console.warn(`  ⚠️ 物件 ${index} 轉換失敗: ${e.message}`);
            return { error: `轉換失敗: ${e.message}`, index };
          }
        });
        
        data.objects[objectType] = convertedArray;
        data.summary.totalObjects += convertedArray.length;
        console.log(`✓ ${objectType}: ${convertedArray.length} 個物件`);
        
      } catch (e) {
        // 嘗試不同的查詢方式
        try {
          console.log(`  ⓘ 嘗試替代方式讀取 ${objectType}...`);
          
          // 某些嵌入式物件可能需要通過過濾器來存取
          const objects = realm.objects(objectType).filtered('TRUEPREDICATE');
          const objectArray = Array.from(objects);
          
          if (objectArray.length > 0) {
            const convertedArray = objectArray.map((obj, index) => {
              try {
                return convertObject(obj);
              } catch (e) {
                return { error: `轉換失敗: ${e.message}`, index };
              }
            });
            
            data.objects[objectType] = convertedArray;
            data.summary.totalObjects += convertedArray.length;
            console.log(`✓ ${objectType}: ${convertedArray.length} 個物件 (替代方式)`);
          } else {
            console.log(`⊘ ${objectType}: 無法通過替代方式存取`);
          }
        } catch (e2) {
          console.warn(`❌ ${objectType}: ${e.message}`);
          data.summary.failedTypes = data.summary.failedTypes || [];
          data.summary.failedTypes.push({ type: objectType, error: e.message });
        }
      }
    }

    console.log(`\n✅ 總共萃取: ${data.summary.totalObjects} 個物件\n`);

    // 根據格式匯出
    if (format === 'csv') {
      await exportToCSV(data);
    } else {
      await exportToJSON(data);
    }

    realm.close();
    console.log('✅ 匯出完成！');

  } catch (error) {
    console.error('❌ 錯誤:', error.message);
    process.exit(1);
  }
}

/**
 * 將 Realm 物件轉換為可序列化的 JavaScript 物件
 * @param {*} obj - 要轉換的物件
 * @param {Set} seen - 已訪問的物件集合（防止循環引用）
 * @param {number} depth - 當前遞歸深度
 * @param {number} maxDepth - 最大遞歸深度
 */
function convertObject(obj, seen = new Set(), depth = 0, maxDepth = 3) {
  // 防止無限遞歸
  if (depth > maxDepth) {
    return '[深度限制]';
  }
  
  // 防止循環引用
  if (typeof obj === 'object' && obj !== null) {
    if (seen.has(obj)) {
      return '[循環引用]';
    }
    seen = new Set(seen);
    seen.add(obj);
  }
  
  const converted = {};
  
  try {
    // 遍歷物件的所有屬性
    const keys = Object.keys(obj);
    
    for (const key of keys) {
      try {
        const value = obj[key];
        
        // 處理不同的數據類型
        if (value === null || value === undefined) {
          converted[key] = null;
        } else if (value instanceof Date) {
          converted[key] = value.toISOString();
        } else if (typeof value === 'boolean' || typeof value === 'number' || typeof value === 'string') {
          converted[key] = value;
        } else if (Array.isArray(value)) {
          // 處理陣列，限制元素數量以避免記憶體溢出
          const maxArrayLength = 100;
          const limitedArray = value.slice(0, maxArrayLength);
          converted[key] = limitedArray.map(v => {
            try {
              if (typeof v === 'object' && v !== null) {
                return convertObject(v, seen, depth + 1, maxDepth);
              }
              return v;
            } catch (e) {
              return `[錯誤: ${e.message}]`;
            }
          });
          if (value.length > maxArrayLength) {
            converted[key + '_count'] = `${value.length} 元素 (只顯示前 ${maxArrayLength})`;
          }
        } else if (typeof value === 'object') {
          // 嘗試轉換嵌套物件
          try {
            converted[key] = convertObject(value, seen, depth + 1, maxDepth);
          } catch (e) {
            // 如果轉換失敗，記錄錯誤
            converted[key] = `[物件] ${e.message}`;
          }
        } else {
          converted[key] = String(value);
        }
      } catch (e) {
        // 跳過無法訪問的屬性
        converted[key] = `[無法訪問: ${e.message}]`;
      }
    }
  } catch (e) {
    console.warn(`警告: 轉換物件時出錯: ${e.message}`);
    return { error: e.message };
  }
  
  return converted;
}

async function exportToJSON(data) {
  console.log(`\n📄 開始匯出為 JSON 格式...\n`);
  
  // 為每種物件類型建立單獨的 JSON 文件
  for (const [objectType, objects] of Object.entries(data.objects)) {
    if (!Array.isArray(objects) || objects.length === 0) {
      console.log(`⊘ ${objectType}: 沒有數據`);
      continue;
    }
    try{
        const folderPath = path.join(__dirname, "export");
        fs.mkdirSync(folderPath, { recursive: true });
    } catch (e) {
        console.warn(`⚠️ 無法建立匯出資料夾: ${e.message}`);
    }
    
    try {
      const fileName = `realm_${objectType.toLowerCase()}.json`;
      const filePath = path.join(__dirname, "export", fileName);
      
      // 建立包含元數據的匯出物件
      const exportObj = {
        type: objectType,
        exportTime: data.exportTime,
        count: objects.length,
        data: objects
      };
      
      fs.writeFileSync(filePath, JSON.stringify(exportObj, null, 2), 'utf8');
      console.log(`✓ ${objectType}: ${objects.length} 個物件已保存至 ${fileName}`);
    } catch (e) {
      console.warn(`⚠️ 無法匯出 ${objectType} 為 JSON: ${e.message}`);
    }
  }
  
  // 同時建立摘要檔案
  try {
    const summaryPath = path.join(__dirname, 'export', 'realm_summary.json');
    const summary = {
      exportTime: data.exportTime,
      totalObjects: data.summary.totalObjects,
      types: data.summary.types,
      typeStats: Object.entries(data.objects).map(([type, objects]) => ({
        type,
        count: Array.isArray(objects) ? objects.length : 0
      })),
      failedTypes: data.summary.failedTypes || []
    };
    
    fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2), 'utf8');
    console.log(`\n✓ 摘要已保存至 realm_summary.json`);
  } catch (e) {
    console.warn(`⚠️ 無法建立摘要檔案: ${e.message}`);
  }
}

async function exportToCSV(data) {
  console.log(`\n📊 開始匯出為 CSV 格式...\n`);
  
  // 對每種物件類型生成 CSV
  for (const [objectType, objects] of Object.entries(data.objects)) {
    if (!Array.isArray(objects) || objects.length === 0) {
      console.log(`⊘ ${objectType}: 沒有數據`);
      continue;
    }
    
    try {
      // 收集所有唯一的鍵（處理不同物件有不同屬性的情況）
      const allKeys = new Set();
      for (const obj of objects) {
        if (typeof obj === 'object' && obj !== null) {
          Object.keys(obj).forEach(key => allKeys.add(key));
        }
      }
      
      const keys = Array.from(allKeys);
      
      if (keys.length === 0) {
        console.log(`⊘ ${objectType}: 物件為空`);
        continue;
      }
      
      // 限制欄位數量以避免 CSV 過於龐大
      const maxColumns = 50;
      const displayKeys = keys.slice(0, maxColumns);
      
      // 轉換物件以適應 CSV 格式
      const csvRecords = objects.map(obj => {
        const record = {};
        for (const key of displayKeys) {
          let value = obj[key];
          
          // 簡化複雜值
          if (value === null || value === undefined) {
            record[key] = '';
          } else if (Array.isArray(value)) {
            record[key] = `[陣列 ${value.length} 元素]`;
          } else if (typeof value === 'object') {
            record[key] = JSON.stringify(value).slice(0, 100); // 限制長度
          } else {
            record[key] = String(value).slice(0, 1000); // 限制字串長度
          }
        }
        return record;
      });
      
      // 建立 CSV writer
      const csvPath = path.join(__dirname, `realm_${objectType.toLowerCase()}.csv`);
      const header = displayKeys.map(key => ({ id: key, title: key }));
      
      const csvWriter = createObjectCsvWriter({
        path: csvPath,
        header: header,
        encoding: 'utf-8'
      });
      
      // 寫入記錄
      await csvWriter.writeRecords(csvRecords);
      
      const columnsInfo = keys.length > maxColumns ? ` (共 ${keys.length} 列，只顯示前 ${maxColumns} 列)` : '';
      console.log(`✓ ${objectType}: ${csvRecords.length} 個物件已保存至 realm_${objectType.toLowerCase()}.csv${columnsInfo}`);
    } catch (e) {
      console.warn(`⚠️ 無法匯出 ${objectType} 為 CSV: ${e.message}`);
    }
  }
}

// 執行匯出
exportRealmData().catch(error => {
  console.error('未處理的錯誤:', error);
  process.exit(1);
});

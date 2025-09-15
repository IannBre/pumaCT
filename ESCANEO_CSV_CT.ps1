##---------------------------------------
# CONFIGURACIÓN
#---------------------------------------

<#
$carpetaFotos = "H:\CT_puma\PNML\PNML20_JackN\2022marzo-octubre" # Carpeta de fotos que tienen problemas de fechas
$csvOut = "H:\CT_puma\PNML\PNML20_JackN\PNML10_JackN_2022marzo-octubre.csv" # Exportar a CSV
$batchSize = 100   # número de fotos por lote
$tempList = "H:\CT_puma\PNML\temp_filelist.txt"

#PREPARACIÓN DE ARCHIVO
if (Test-Path $csvOut) { Remove-Item $csvOut }
Add-Content -Path $csvOut -Value "SourceFile,DateTimeOriginal,CreateDate,ModifyDate,FileSize,ImageWidth,ImageHeight,Subject"

#LISTA DE ARCHIVOS
$fotos = Get-ChildItem -Path $carpetaFotos -Filter *.JPG -Recurse
$total = $fotos.Count
Write-Host "Se encontraron $total fotos en $carpetaFotos"

#---------------------------------------
# PROCESAMIENTO POR LOTES CON PROGRESO
#---------------------------------------
for ($i=0; $i -lt $total; $i += $batchSize) {
   $batch = $fotos[$i..([math]::Min($i+$batchSize-1, $total-1))]

    $percent = [math]::Round(($i / $total) * 100, 2)
    Write-Progress -Activity "Extrayendo metadatos con exiftool" `
                  -Status "Procesando fotos $i a $([math]::Min($i+$batchSize,$total)) de $total" `
                 -PercentComplete $percent

    # Guardar nombres de archivos del batch en TXT
   $batch.FullName | Out-File -FilePath $tempList -Encoding UTF8

    # Usar exiftool con lista de archivos
   exiftool -csv -DateTimeOriginal -CreateDate -ModifyDate -FileSize -ImageWidth -ImageHeight -Subject -@ $tempList 2>$null |
     Select-Object -Skip 1 | Out-File -FilePath $csvOut -Encoding UTF8 -Append
}

# FINALIZACIÓN
Remove-Item $tempList -ErrorAction SilentlyContinue
Write-Progress -Activity "Extrayendo metadatos con exiftool" -Completed
Write-Host "✅ Exportación finalizada. Archivo guardado en: $csvOut"

#>


#--------------------------------------------------------------------
# CONFIGURACIÓN DE RUTAS PARA BUSCAR LAS FOTOS Y HACER LA OPERACION
#------------------------------------------------------------------
$carpetaOriginal = "F:\CamarasPuma\PN_Monte_Leon\2023-2024\Jack norte\DCIM\2022marzo-octubre"
$carpetaEditadas = "H:\CT_puma\PNML\PNML20_JackN\2022marzo-octubre"
$carpetaSalida = "H:\CT_puma\PNML_CORREGIDO\PMML20_JackN\2022marzo-octubre"

$csvFile = "H:\CT_puma\PNML\PNML20_JackN\PNML10_JackN_2022marzo-octubre.csv"   # Ruta al CSV con fotos problemáticas DEBRIA SER IGUAL A $csvOut SI CORRI ANTES LAS LINES DE ARRIBA DEL CSV
$progressFile = "H:\CT_puma\progreso_PNML20_JackN_2022marzo-octubre.txt"
$resumenCSV = "H:\CT_puma\resumen_etiquetas_PNML20_JackN_2022marzo-octubre.csv"

#---------------------------------------
# CONFIGURACIÓN CONTROLADA DE REVISION DE IMÁGENES
#---------------------------------------
$limiteFotos = 2000   # Número máximo de fotos a procesar en esta corrida

#---------------------------------------
# PREPARACIÓN DE CARPETAS Y LOG
#---------------------------------------
if (-not (Test-Path $carpetaSalida)) { New-Item -ItemType Directory -Path $carpetaSalida }

$logFile = "H:\CT_puma\log_PNML20_JackN_$((Get-Date).ToString('yyyyMMdd')).txt"
if (-not (Test-Path $logFile)) { "" | Out-File $logFile }

"" | Out-File $resumenCSV
Add-Content -Path $resumenCSV -Value "Foto,Estado,FechaHora"

$inicio = Get-Date
Add-Content -Path $logFile -Value "`n============================="
Add-Content -Path $logFile -Value "Inicio del proceso: $inicio"
Write-Host "Inicio del proceso: $inicio"

# Inicializar contadores
$contadorTransferidas = 0
$contadorSinOriginal = 0
$contadorDimensiones = 0
$contadorSinXMP = 0
$contadorTotal = 0

# RETOMAR DESDE LA ÚLTIMA FOTO
$inicioDesde = 0
if (Test-Path $progressFile) {
    $inicioDesde = [int](Get-Content $progressFile | Select-Object -Last 1)
    Write-Host "Retomando desde foto índice: $inicioDesde"
}

#--------------------------------------------------------------------
# CARGAR CSV Y FILTRAR POR ÚLTIMA CARPETA
#--------------------------------------------------------------------
$csv = Import-Csv -Path $csvFile -Delimiter "," #VER DELIMITADOR!!!!!!!!!!!!!!!!!!!!!!!!! SI EL CSV ES DE R, HACE ";" Y SI ES DE POWERSHELL ES CON ","

$ultimaCarpeta = Split-Path $carpetaEditadas -Leaf

$fotosCSV = $csv | Where-Object {
    ($_.SourceFile -and $_.SourceFile.Trim() -ne "") -and
    (-not $_.DateTimeOriginal -or $_.DateTimeOriginal.Trim() -eq "") -and
    ($_.SourceFile -like "*$ultimaCarpeta*")
} | Select-Object -Skip $inicioDesde -First $limiteFotos

Write-Host "Filas del CSV seleccionadas para procesar: $($fotosCSV.Count)"

$archivosOriginales = Get-ChildItem $carpetaOriginal -Filter *.JPG

#--------------------------------------------------------------------

#--------------------------------------------------------------------
# FUNCIONES
#--------------------------------------------------------------------
function Leer-Dimensiones {
    param([string]$archivo)
    $dim = & exiftool -ImageWidth -ImageHeight -s -s -s $archivo
    $split = $dim -split "\s+"
    return @([int]$split[0],[int]$split[1])
}

function Transferir-Etiqueta {
    param(
        [string]$editada,
        [array]$originales,
        [string]$carpetaSalida,
        [string]$logFile,
        [string]$resumenCSV,
        [int]$filaCSV
    )
    $nuevoArchivo = "$carpetaSalida\$($originales[0].Name)"
    foreach ($orig in $originales) {
        exiftool -TagsFromFile $editada -XMP:All -EXIF:All -o $nuevoArchivo $orig.FullName
    }
    Add-Content $logFile "Fila CSV  ${filaCSV}: Etiqueta transferida: $($originales[0].Name)"
    Add-Content $resumenCSV "$($originales[0].Name),Transferida,$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),$filaCSV"
}

#--------------------------------------------------------------------
# PROCESAMIENTO PRINCIPAL
#--------------------------------------------------------------------
foreach ($fila in $fotosCSV) {

    $contadorTotal++
    $filaCSV = $contadorTotal + $inicioDesde  # número de fila en CSV
    $rutaEditada = $fila.SourceFile -replace "/", "\"

    # Barra de progreso
    $porcentaje = [math]::Round(($contadorTotal / $fotosCSV.Count) * 100, 2)
    Write-Progress -Activity "Procesando fotos" -Status "Fila $filaCSV de $($fotosCSV.Count)" -PercentComplete $porcentaje
    
    # Verificar que la foto editada exista
    if (-not (Test-Path $rutaEditada)) {
        Write-Host "Archivo editado no encontrado: $rutaEditada" -ForegroundColor Red
        Add-Content $logFile "Fila CSV ${filaCSV}: Sin archivo editado: $rutaEditada"
        Add-Content $resumenCSV "$rutaEditada,Sin archivo editado,$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),$filaCSV"
        $contadorSinOriginal++
        continue
    }

    $editada = Get-Item $rutaEditada
    if ($editada.Extension -notin ".JPG",".jpg") { continue }

    # Extraer carpeta contenedora del CSV
    $carpetaCSV = Split-Path $rutaEditada -Parent | Split-Path -Leaf
    $nombreArchivo = $editada.Name

    # Buscar originales con mismo nombre y que contengan la carpeta del CSV en su ruta
    $originalesCoincidentes = $archivosOriginales | Where-Object {
        $_.Name -eq $nombreArchivo -and $_.FullName -match [regex]::Escape($carpetaCSV)
    }

    if ($originalesCoincidentes.Count -eq 0) {
        Write-Host "Original no encontrado (nombre y carpeta coincidente): $nombreArchivo" -ForegroundColor Red
        Add-Content $logFile "Fila CSV ${filaCSV}: Sin original: $nombreArchivo"
        Add-Content $resumenCSV "$nombreArchivo,Sin original,$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),$filaCSV"
        $contadorSinOriginal++
        continue
    }

    # Leer dimensiones de la editada
    $dimsEditada = Leer-Dimensiones $editada.FullName

    foreach ($original in $originalesCoincidentes) {
        $dimsOriginal = Leer-Dimensiones $original.FullName

# Revisar si hay etiquetas XMP
$xmpAll = exiftool -s -s -s -XMP:All $editada.FullName

if ($xmpAll -and $xmpAll.Trim() -ne "") {
    # Transferir etiquetas incluso si las dimensiones no coinciden
    Transferir-Etiqueta -editada $editada.FullName -originales $originalesCoincidentes `
        -carpetaSalida $carpetaSalida -logFile $logFile -resumenCSV $resumenCSV -filaCSV $filaCSV
    $contadorTransferidas++

    if ($dimsOriginal[0] -ne $dimsEditada[0] -or $dimsOriginal[1] -ne $dimsEditada[1]) {
        Write-Host "⚠ Dimensiones no coinciden pero se transfirió etiqueta: $($editada.Name)" -ForegroundColor Yellow
        Add-Content $logFile "Fila CSV ${filaCSV}: Dimensiones no coinciden pero se transfirió etiqueta: $($editada.Name)"
        $contadorDimensiones++
    }
} elseif (-not $fila.DateTimeOriginal -or $fila.DateTimeOriginal.Trim() -eq "") {
    # Caso sin fecha y sin XMP
    Write-Host "Fila CSV ${filaCSV}: SIN FECHA Y SIN ETIQUETA: $($editada.Name)" -ForegroundColor Yellow
    Add-Content $logFile "Fila CSV ${filaCSV}: SIN FECHA Y SIN ETIQUETA: $($editada.Name)"
    Add-Content $resumenCSV "$($editada.FullName),SIN FECHA Y SIN ETIQUETA,$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),$filaCSV"
    $contadorSinXMP++
} else {
    # Solo sin XMP pero con fecha
    Write-Host "Fila CSV ${filaCSV}: Sin etiquetas XMP: $($editada.Name)"
    Add-Content $logFile "Fila CSV ${filaCSV}: Sin etiquetas XMP: $($editada.Name)"
    Add-Content $resumenCSV "$($editada.FullName),Sin XMP,$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),$filaCSV"
    $contadorSinXMP++
}

    }

    # Guardar progreso
    Set-Content $progressFile ($inicioDesde + $contadorTotal)
}

#--------------------------------------------------------------------
# RESUMEN FINAL
#--------------------------------------------------------------------
$fin = Get-Date
Add-Content $logFile "`n============================="
Add-Content $logFile "Proceso finalizado: $fin"
Add-Content $logFile "Duración: $([math]::Round(($fin - $inicio).TotalMinutes,2)) minutos"
Add-Content $logFile "Resumen: Total=$contadorTotal, Transferidas=$contadorTransferidas, Sin original=$contadorSinOriginal, Dimensiones=$contadorDimensiones, Sin XMP=$contadorSinXMP"

Add-Content $resumenCSV ""
Add-Content $resumenCSV "Resumen final"
Add-Content $resumenCSV "Total procesadas,$contadorTotal"
Add-Content $resumenCSV "Transferidas,$contadorTransferidas"
Add-Content $resumenCSV "Sin original,$contadorSinOriginal"
Add-Content $resumenCSV "Dimensiones distintas,$contadorDimensiones"
Add-Content $resumenCSV "Sin XMP,$contadorSinXMP"

Write-Host "Proceso finalizado. Revisar log en $logFile"
Write-Host "Resumen CSV generado en: $resumenCSV"

Add-Content $logFile "---- IannB - CIMaF 2025 ----"








#--------------------------------------------------------------------
# RECUPERAR ETIQUETAS XMP DESDE EDITADAS A ORIGINALES + CSV CONTROL
#--------------------------------------------------------------------

<#

$resumenCSV = "H:\CT_puma\PNML\PNML20_JackN\PNML10_JackN_2022marzo-octubre.csv" #resultado de la transferencia
# CSV con las fotos que fallaron
$csvErrores = $resumenCSV
# Carpeta donde están las fotos originales (con fecha correcta)
$carpetaOriginales = "F:\CamarasPuma\PN_Monte_Leon\2023-2024\Jack norte\DCIM\2022marzo-octubre"
# Carpeta donde están las fotos editadas (con XMP)
$carpetaEditadas   = "H:\CT_puma\PNML\PNML20_JackN\2022marzo-octubre"
# Carpeta donde se guardarán las fotos con metadata transferida
$carpetaSalida     = "H:\CT_puma\PNML_CORREGIDO\PNML20_JackN\2022marzo-octubre\solucionadas"
if (!(Test-Path $carpetaSalida)) { New-Item -ItemType Directory -Path $carpetaSalida }
# CSV de control de salida
$csvControl = "H:\CT_puma\PNML_CORREGIDO\PNML20_JackN\control_recuperacion.csv"

# Log
$logFile = "H:\CT_puma\PNML_CORREGIDO\PNML20_JackN\PNML20_JackN_recuperacion.log"
if (Test-Path $logFile) { Remove-Item $logFile }
if (Test-Path $csvControl) { Remove-Item $csvControl }

# Leer todas las filas del CSV
$lineas = Get-Content $resumenCSV

# Filtrar solo filas problemáticas:
# - empiezan con ruta H:\CT_puma\ 
# - o contienen "Sin archivo editado"
# - o tienen muchas comas después del JPG
$errores = $lineas | Where-Object { 
    #$_ -like '"H:\CT_puma\*"' -or $_ -match 'Sin archivo editado' -or ($_ -match '\.JPG,{2,}') 
    $_ -like ($_ -match '\.JPG,{2,}')
}

$total = $errores.Count
$index = 0
$resultados = @()

foreach ($fila in $errores) {
    $index++

    # Extraer nombre de archivo
    if ($fila -match '([\w_]+\.JPG)') {
        $fileName = $matches[1]
    } else {
        Write-Host "⚠ No se pudo extraer nombre de archivo de la fila: $fila"
        Add-Content $logFile "⚠ No se pudo extraer nombre de archivo de la fila: $fila"
        continue
    }

    Write-Progress -Activity "Recuperando etiquetas XMP" `
                   -Status "Procesando $index de $total ($fileName)" `
                   -PercentComplete (($index / $total) * 100)

    # Buscar original
    $original = Get-ChildItem -Path $carpetaOriginales -Recurse -Filter $fileName | Select-Object -First 1
    # Buscar editada
    $editadaPath = Join-Path $carpetaEditadas $fileName
    $editada = if (Test-Path $editadaPath) { Get-Item $editadaPath } else { $null }

    # Ruta de salida
    if ($original) {
        $salidaPath = Join-Path $carpetaSalida $fileName
        Copy-Item -Path $original.FullName -Destination $salidaPath -Force
    }

    # Transferir XMP si hay editada
    if ($original -and $editada) {
        Write-Host "✔ Copiando Subject de $($editada.FullName) -> $salidaPath"
        Add-Content $logFile "✔ Copiando Subject de $($editada.FullName) -> $salidaPath"

        & exiftool -TagsFromFile $editada.FullName "-XMP:Subject" -overwrite_original $salidaPath | Out-Null
    }
    elseif ($original -and -not $editada) {
        Write-Host "⚠ No se encontró editada para $fileName"
        Add-Content $logFile "⚠ No se encontró editada para $fileName"
    }
    elseif (-not $original -and $editada) {
        Write-Host "⚠ No se encontró original para $fileName"
        Add-Content $logFile "⚠ No se encontró original para $fileName"
    }
    else {
        Write-Host "⚠ No se encontró ni original ni editada para $fileName"
        Add-Content $logFile "⚠ No se encontró ni original ni editada para $fileName"
    }

    # Guardar metadata en CSV si hay original
    if ($original) {
        $resultados += [PSCustomObject]@{
            FileName         = $fileName
            SourceFile       = $salidaPath
            DateTimeOriginal = (& exiftool -s3 -DateTimeOriginal $salidaPath)
            CreateDate       = (& exiftool -s3 -CreateDate $salidaPath)
            ModifyDate       = (& exiftool -s3 -ModifyDate $salidaPath)
            FileSize         = (& exiftool -s3 -FileSize $salidaPath)
            ImageWidth       = (& exiftool -s3 -ImageWidth $salidaPath)
            ImageHeight      = (& exiftool -s3 -ImageHeight $salidaPath)
            Subject          = (& exiftool -s3 -XMP:Subject $salidaPath)
        }
    }
}

# Exportar CSV de control
if ($resultados.Count -gt 0) {
    $resultados | Export-Csv -Path $csvControl -NoTypeInformation -Encoding UTF8
    Write-Host "`n✅ Proceso terminado. Revisar log en: $logFile"
    Write-Host "📂 CSV de control generado en: $csvControl"
} else {
    Write-Host "⚠ No se recuperó ninguna foto, revisar log."
}
    #>

<#
    #Proceso en lote para cambiar nombre de fotos

    # Carpeta con las fotos
$carpeta = "H:\CT_puma\PNML\PNML20_JackN\2022marzo-octubre"

# Buscar todos los archivos que terminen con (2).*
Get-ChildItem -Path $carpeta -Filter "* (2).*" | ForEach-Object {
    $nuevoNombre = $_.Name -replace ' \(2\)', ''
    Rename-Item -Path $_.FullName -NewName $nuevoNombre
}
 #>


#<#

#Proceso en lote para cambiar fecha de fotos con EXIFTOOL

# Carpeta de entrada (fotos con año incorrecto) CON ETIQUETA
$carpetaOrigen   = "H:\CT_puma\PNML\PNML11_RepetidoraN\2022marzo-octubre"

# Carpeta de salida (fotos con fecha corregida)
$carpetaDestino  = "H:\CT_puma\PNML_CORREGIDO\PNML11_RepetidoraN\fecha_corregida"

# CSV de control
$csvControl      = "H:\CT_puma\PNML_CORREGIDO\PNML11_RepetidoraN\control_fechas.csv"

# Log del proceso
$logFile         = "H:\CT_puma\PNML_CORREGIDO\PNML11_RepetidoraN\fecha_corregida.log"

# Crear carpeta destino si no existe
if (!(Test-Path $carpetaDestino)) { 
    New-Item -ItemType Directory -Path $carpetaDestino | Out-Null
}

# Limpiar logs previos
if (Test-Path $csvControl) { Remove-Item $csvControl }
if (Test-Path $logFile) { Remove-Item $logFile }

# Obtener lista de fotos
$fotos = Get-ChildItem -Path $carpetaOrigen -Filter *.JPG
$total = $fotos.Count
$index = 0
$resultados = @()
$ok = 0
$fail = 0

foreach ($foto in $fotos) {
    $index++
    $fileName = $foto.Name

    Write-Progress -Activity "Corrigiendo fechas EXIF" `
                   -Status "Procesando $index de $total ($fileName)" `
                   -PercentComplete (($index / $total) * 100)

    try {
        # Leer fecha original antes de modificar
        $fechaOriginal = & exiftool -s3 -DateTimeOriginal $foto.FullName

        # Generar ruta de salida
        $salida = Join-Path $carpetaDestino $fileName

        # Corregir fecha sumando un año (mantiene horas y minutos)
        & exiftool `
          "-DateTimeOriginal+=1:0:0 0" `
          "-CreateDate+=1:0:0 0" `
          "-ModifyDate+=1:0:0 0" `
          -o $salida $foto.FullName | Out-Null

        # Leer nueva fecha
        $fechaNueva = & exiftool -s3 -DateTimeOriginal $salida

        # Guardar en resultados
        $resultados += [PSCustomObject]@{
            FileName        = $fileName
            FechaOriginal   = $fechaOriginal
            FechaNueva      = $fechaNueva
            FileSize        = (& exiftool -s3 -FileSize $salida)
            ImageWidth      = (& exiftool -s3 -ImageWidth $salida)
            ImageHeight     = (& exiftool -s3 -ImageHeight $salida)
        }

        $ok++
        Add-Content $logFile "✔ $fileName | $fechaOriginal -> $fechaNueva"
    }
    catch {
        $fail++
        Add-Content $logFile "⚠ ERROR con $fileName : $_"
    }
}

# Exportar CSV de control
if ($resultados.Count -gt 0) {
    $resultados | Export-Csv -Path $csvControl -NoTypeInformation -Encoding UTF8
}

# Resumen final en log
Add-Content $logFile ""
Add-Content $logFile "===== RESUMEN ====="
Add-Content $logFile "Total procesadas : $total"
Add-Content $logFile "Correctas        : $ok"
Add-Content $logFile "Fallidas         : $fail"
Add-Content $logFile "CSV de control   : $csvControl"

Write-Host "`n✅ Proceso terminado. Log en: $logFile"
Write-Host "📂 CSV de control generado en: $csvControl"


 #>

 
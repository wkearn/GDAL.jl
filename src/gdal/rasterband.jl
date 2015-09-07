@doc """
Fetch the "natural" block size of this band.

GDAL contains a concept of the natural block size of rasters so that
applications can organized data access efficiently for some file formats.
The natural block size is the block size that is most efficient for accessing
the format. For many formats this is simple a whole scanline in which case
*pnXSize is set to GetXSize(), and *pnYSize is set to 1.

However, for tiled images this will typically be the tile size.

Note that the X and Y block sizes don't have to divide the image size evenly,
meaning that right and bottom edge blocks may be incomplete. See ReadBlock()
for an example of code dealing with these issues.

Returns:
(x,y)::Tuple{Cint,Cint}    for both the X block size, and Y block size
""" ->
function _block_size(rasterband::GDALRasterBandH)
    x = Ref{Cint}(); y = Ref{Cint}()
    GDALGetBlockSize(rasterband, x, y)
    (x == C_NULL || y == C_NULL) && error("Failed to get block size")
    (x[], y[])
end

@doc "Fetch the pixel data type for this band." ->
_band_type(rasterband::GDALRasterBandH) = GDALGetRasterDataType(rasterband)

@doc """
Read/write a region of image data for this band.

This method allows reading a region of a GDALRasterBand into a buffer, or
writing data from a buffer into a region of a GDALRasterBand. It automatically
takes care of data type translation if the data type (eBufType) of the buffer
is different than that of the GDALRasterBand. The method also takes care of
image decimation / replication if the buffer size (nBufXSize x nBufYSize) is
different than the size of the region being accessed (nXSize x nYSize).

The nPixelSpace and nLineSpace parameters allow reading into or writing from
unusually organized buffers. This is primarily used for buffers containing more
than one bands raster data in interleaved format.

Some formats may efficiently implement decimation into a buffer by reading from
lower resolution overview images.

For highest performance full resolution data access, read and write on "block
boundaries" returned by GetBlockSize(), or use the ReadBlock() and WriteBlock()
methods.

Parameters:
eRWFlag     Either GF_Read to read a region of data, or GF_Write to write a
            region of data.
nXOff       The pixel offset to the top left corner of the region of the band
            to be accessed. This would be zero to start from the left side.
nYOff       The line offset to the top left corner of the region of the band
            to be accessed. This would be zero to start from the top.
nXSize      The width of the region of the band to be accessed in pixels.
nYSize      The height of the region of the band to be accessed in lines.
pData       The buffer into which the data should be read, or from which it
            should be written. This buffer must contain at least
            nBufXSize * nBufYSize words of type eBufType. It is organized in
            left to right, top to bottom pixel order. Spacing is controlled by
            the nPixelSpace, and nLineSpace parameters.
nBufXSize   the width of the buffer image into which the desired region is to
            be read, or from which it is to be written.
nBufYSize   the height of the buffer image into which the desired region is to
            be read, or from which it is to be written.
eBufType    the type of the pixel values in the pData data buffer. The pixel
            values will automatically be translated to/from the GDALRasterBand
            data type as needed.
nPixelSpace The byte offset from the start of one pixel value in pData to the
            start of the next pixel value within a scanline. If defaulted (0)
            the size of the datatype eBufType is used.
nLineSpace  The byte offset from the start of one scanline in pData to the
            start of the next. If defaulted (0) the size of the datatype
            eBufType * nBufXSize is used.
psExtraArg  (new in GDAL 2.0) pointer to a GDALRasterIOExtraArg structure with
            additional arguments to specify resampling and progress callback,
            or NULL for default behaviour. The GDAL_RASTERIO_RESAMPLING
            configuration option can also be defined to override the default
            resampling to one of BILINEAR, CUBIC, CUBICSPLINE, LANCZOS, AVERAGE
            or MODE.

Returns:
CE_Failure if the access fails, otherwise CE_None.
"""-> 
function _raster_io!{T <: Real}(rasterband::GDALRasterBandH,
                                buffer::Array{T,2},
                                width::Cint,
                                height::Cint,
                                xoffset::Cint = 0,
                                yoffset::Cint = 0,
                                access::GDALRWFlag = GF_Read,
                                nPixelSpace::Cint = 0,
                                nLineSpace::Cint = 0)
    xsize, ysize = size(buffer)
    io_error = GDALRasterIO(rasterband, access, xoffset, yoffset, width,
                            height, Ptr{Void}(pointer(buffer)), xsize, ysize,
                            _gdal_type(Val{T}), nPixelSpace, nLineSpace)
    (io_error == CE_Failure) && error("Failed to access raster band")
    buffer
end

function _raster_io!{T <: Real}(band::GDALRasterBandH,
                                buffer::Array{T,2},
                                access::GDALRWFlag = GF_Read,
                                nPixelSpace::Cint = 0,
                                nLineSpace::Cint = 0)
    _raster_io!(rasterband, buffer, _band_xsize(band), _band_ysize(band),
                Cint(0), Cint(0), access, nPixelSpace, nLineSpace)
end

function _raster_io!{T <: Real}(rasterband::GDALRasterBandH,
                                buffer::Array{T,2},
                                rows::UnitRange{Int},
                                cols::UnitRange{Int},
                                access::GDALRWFlag = GF_Read,
                                nPixelSpace::Cint = 0,
                                nLineSpace::Cint = 0)
    width = cols[end] - cols[1]; width < 0 && error("invalid window width")
    height = rows[end] - rows[1]; height < 0 && error("invalid window height")
    _raster_io!(rasterband, buffer, width, height, cols[1], rows[1], access,
                nPixelSpace, nLineSpace)
end

@doc "Fetch the width in pixels of this band." ->
_band_xsize(rasterband::GDALRasterBandH) = GDALGetRasterBandXSize(rasterband)

@doc "Fetch the height in pixels of this band." ->
_band_ysize(rasterband::GDALRasterBandH) = GDALGetRasterBandXSize(rasterband)

@doc "Find out if we have update permission for this band." ->
# function GDALGetRasterAccess(arg1::GDALRasterBandH)
#     ccall((:GDALGetRasterAccess,libgdal),GDALAccess,(GDALRasterBandH,),arg1)
# end

@doc """Fetch the band number (1+) within its dataset, or 0 if unknown.

This method may return a value of 0 to indicate GDALRasterBand objects without
a relationship to a dataset, such as GDALRasterBands serving as overviews.
""" ->
_band_number(rasterband::GDALRasterBandH) = GDALGetBandNumber(rasterband)

@doc """
Fetch the handle to its dataset handle, or NULL if this cannot be determined.

Note that some GDALRasterBands are not considered to be a part of a dataset,
such as overviews or other "freestanding" bands.
""" ->

_band_dataset(rasterband::GDALRasterBandH) = GDALGetBandDataset(rasterband)

@doc """
Return raster unit type.

Return a name for the units of this raster's values. For instance, it might be "m" for an elevation model in meters, or "ft" for feet. If no units are available, a value of "" will be returned. The returned string should not be modified, nor freed by the calling application.

This method is the same as the C function GDALGetRasterUnitType().

Returns:
unit name string.
""" ->
# function GDALGetRasterUnitType(arg1::GDALRasterBandH)
#     ccall((:GDALGetRasterUnitType,libgdal),Ptr{Uint8},(GDALRasterBandH,),arg1)
# end

@doc "Set unit type." ->
# function GDALSetRasterUnitType(hBand::GDALRasterBandH,pszNewValue::Ptr{Uint8})
#     ccall((:GDALSetRasterUnitType,libgdal),CPLErr,(GDALRasterBandH,Ptr{Uint8}),hBand,pszNewValue)
# end

@doc """
Fetch the raster value offset.

This value (in combination with the GetScale() value) is used to transform raw
pixel values into the units returned by GetUnits(). For example this might be
used to store elevations in GUInt16 bands with a precision of 0.1, and starting
from -100.

Units value = (raw value * scale) + offset

For file formats that don't know this intrinsically, 0 is returned.

Parameters:
pbSuccess   pointer to a boolean to use to indicate if the returned value is
            meaningful or not. May be NULL (default).

Returns:
the raster offset.
""" ->
function _raster_offset(rasterband::GDALRasterBandH)
    success = Ref{Cint}()
    offset = GDALGetRasterOffset(rasterband, success)
    meaningful = (success == C_NULL) || (success[] != 0)
    (offset, meaningful)
end

# function GDALSetRasterOffset(hBand::GDALRasterBandH,dfNewOffset::Cdouble)
#     ccall((:GDALSetRasterOffset,libgdal),CPLErr,(GDALRasterBandH,Cdouble),hBand,dfNewOffset)
# end

@doc """
Fetch the raster value scale.

This value (in combination with the GetOffset() value) is used to transform raw pixel values into the units returned by GetUnits(). For example this might be used to store elevations in GUInt16 bands with a precision of 0.1, and starting from -100.

Units value = (raw value * scale) + offset

For file formats that don't know this intrinsically a value of one is returned.

This method is the same as the C function GDALGetRasterScale().

Parameters:
pbSuccess   pointer to a boolean to use to indicate if the returned value is meaningful or not. May be NULL (default).
Returns:
the raster scale.
""" ->
# function GDALGetRasterScale(arg1::GDALRasterBandH,pbSuccess::Ptr{Cint})
#     ccall((:GDALGetRasterScale,libgdal),Cdouble,(GDALRasterBandH,Ptr{Cint}),arg1,pbSuccess)
# end

@doc "Set scaling ratio." ->
# function GDALSetRasterScale(hBand::GDALRasterBandH,dfNewOffset::Cdouble)
#     ccall((:GDALSetRasterScale,libgdal),CPLErr,(GDALRasterBandH,Cdouble),hBand,dfNewOffset)
# end

@doc """
Copy all raster band raster data.

This function copies the complete raster contents of one band to another similarly configured band. The source and destination bands must have the same width and height. The bands do not have to have the same data type.

It implements efficient copying, in particular "chunking" the copy in substantial blocks.

Currently the only papszOptions value supported is : "COMPRESSED=YES" to force alignment on target dataset block sizes to achieve best compression. More options may be supported in the future.

Parameters:
hSrcBand    the source band
hDstBand    the destination band
papszOptions    transfer hints in "StringList" Name=Value format.
pfnProgress     progress reporting function.
pProgressData   callback data for progress function.
Returns:
CE_None on success, or CE_Failure on failure.
""" ->
# function GDALRasterBandCopyWholeRaster(hSrcBand::GDALRasterBandH,hDstBand::GDALRasterBandH,papszOptions::Ptr{Ptr{Uint8}},pfnProgress::GDALProgressFunc,pProgressData::Ptr{Void})
#     ccall((:GDALRasterBandCopyWholeRaster,libgdal),CPLErr,(GDALRasterBandH,GDALRasterBandH,Ptr{Ptr{Uint8}},GDALProgressFunc,Ptr{Void}),hSrcBand,hDstBand,papszOptions,pfnProgress,pProgressData)
# end

@doc """
Generate downsampled overviews.

This function will generate one or more overview images from a base image using the requested downsampling algorithm. It's primary use is for generating overviews via GDALDataset::BuildOverviews(), but it can also be used to generate downsampled images in one file from another outside the overview architecture.

The output bands need to exist in advance.

The full set of resampling algorithms is documented in GDALDataset::BuildOverviews().

This function will honour properly NODATA_VALUES tuples (special dataset metadata) so that only a given RGB triplet (in case of a RGB image) will be considered as the nodata value and not each value of the triplet independantly per band.

Parameters:
hSrcBand    the source (base level) band.
nOverviewCount  the number of downsampled bands being generated.
pahOvrBands     the list of downsampled bands to be generated.
pszResampling   Resampling algorithm (eg. "AVERAGE").
pfnProgress     progress report function.
pProgressData   progress function callback data.
Returns:
CE_None on success or CE_Failure on failure.
""" ->
# function GDALRegenerateOverviews(hSrcBand::GDALRasterBandH,nOverviewCount::Cint,pahOverviewBands::Ptr{GDALRasterBandH},pszResampling::Ptr{Uint8},pfnProgress::GDALProgressFunc,pProgressData::Ptr{Void})
#     ccall((:GDALRegenerateOverviews,libgdal),CPLErr,(GDALRasterBandH,Cint,Ptr{GDALRasterBandH},Ptr{Uint8},GDALProgressFunc,Ptr{Void}),hSrcBand,nOverviewCount,pahOverviewBands,pszResampling,pfnProgress,pProgressData)
# end

@doc "Advise driver of upcoming read requests." ->
# function GDALRasterAdviseRead(hRB::GDALRasterBandH,nDSXOff::Cint,nDSYOff::Cint,nDSXSize::Cint,nDSYSize::Cint,nBXSize::Cint,nBYSize::Cint,eBDataType::GDALDataType,papszOptions::Ptr{Ptr{Uint8}})
#     ccall((:GDALRasterAdviseRead,libgdal),CPLErr,(GDALRasterBandH,Cint,Cint,Cint,Cint,Cint,Cint,GDALDataType,Ptr{Ptr{Uint8}}),hRB,nDSXOff,nDSYOff,nDSXSize,nDSYSize,nBXSize,nBYSize,eBDataType,papszOptions)
# end

@doc """
Read a block of image data efficiently.

This method accesses a "natural" block from the raster band without resampling, or data type conversion. For a more generalized, but potentially less efficient access use RasterIO().

This method is the same as the C GDALReadBlock() function.

See the GetLockedBlockRef() method for a way of accessing internally cached block oriented data without an extra copy into an application buffer.

Parameters:
nXBlockOff  the horizontal block offset, with zero indicating the left most block, 1 the next block and so forth.
nYBlockOff  the vertical block offset, with zero indicating the left most block, 1 the next block and so forth.
pImage  the buffer into which the data will be read. The buffer must be large enough to hold GetBlockXSize()*GetBlockYSize() words of type GetRasterDataType().
Returns:
CE_None on success or CE_Failure on an error.
""" ->
# function GDALReadBlock(arg1::GDALRasterBandH,arg2::Cint,arg3::Cint,arg4::Ptr{Void})
#     ccall((:GDALReadBlock,libgdal),CPLErr,(GDALRasterBandH,Cint,Cint,Ptr{Void}),arg1,arg2,arg3,arg4)
# end

@doc """
Write a block of image data efficiently.

This method accesses a "natural" block from the raster band without resampling, or data type conversion. For a more generalized, but potentially less efficient access use RasterIO().

This method is the same as the C GDALWriteBlock() function.

See ReadBlock() for an example of block oriented data access.

Parameters:
nXBlockOff  the horizontal block offset, with zero indicating the left most block, 1 the next block and so forth.
nYBlockOff  the vertical block offset, with zero indicating the left most block, 1 the next block and so forth.
pImage  the buffer from which the data will be written. The buffer must be large enough to hold GetBlockXSize()*GetBlockYSize() words of type GetRasterDataType().
Returns:
CE_None on success or CE_Failure on an error.
""" ->
# function GDALWriteBlock(arg1::GDALRasterBandH,arg2::Cint,arg3::Cint,arg4::Ptr{Void})
#     ccall((:GDALWriteBlock,libgdal),CPLErr,(GDALRasterBandH,Cint,Cint,Ptr{Void}),arg1,arg2,arg3,arg4)
# end

@doc """
Check for arbitrary overviews.

This returns TRUE if the underlying datastore can compute arbitrary overviews efficiently, such as is the case with OGDI over a network. Datastores with arbitrary overviews don't generally have any fixed overviews, but the RasterIO() method can be used in downsampling mode to get overview data efficiently.

This method is the same as the C function GDALHasArbitraryOverviews(),

Returns:
TRUE if arbitrary overviews available (efficiently), otherwise FALSE.
""" ->
# function GDALHasArbitraryOverviews(arg1::GDALRasterBandH)
#     ccall((:GDALHasArbitraryOverviews,libgdal),Cint,(GDALRasterBandH,),arg1)
# end

@doc """
Return the number of overview layers available.

This method is the same as the C function GDALGetOverviewCount().

Returns:
overview count, zero if none.
""" ->
# function GDALGetOverviewCount(arg1::GDALRasterBandH)
#     ccall((:GDALGetOverviewCount,libgdal),Cint,(GDALRasterBandH,),arg1)
# end

@doc """
Fetch overview raster band object.

This method is the same as the C function GDALGetOverview().

Parameters:
i   overview index between 0 and GetOverviewCount()-1.
Returns:
overview GDALRasterBand.
""" ->
# function GDALGetOverview(arg1::GDALRasterBandH,arg2::Cint)
#     ccall((:GDALGetOverview,libgdal),GDALRasterBandH,(GDALRasterBandH,Cint),arg1,arg2)
# end

@doc """
Fetch best sampling overview.

Returns the most reduced overview of the given band that still satisfies the desired number of samples. This function can be used with zero as the number of desired samples to fetch the most reduced overview. The same band as was passed in will be returned if it has not overviews, or if none of the overviews have enough samples.

This method is the same as the C functions GDALGetRasterSampleOverview() and GDALGetRasterSampleOverviewEx().

Parameters:
nDesiredSamples     the returned band will have at least this many pixels.
Returns:
optimal overview or the band itself.
""" ->
# function GDALGetRasterSampleOverview(arg1::GDALRasterBandH,arg2::Cint)
#     ccall((:GDALGetRasterSampleOverview,libgdal),GDALRasterBandH,(GDALRasterBandH,Cint),arg1,arg2)
# end

@doc """
Fetch the no data value for this band.

If there is no out of data value, an out of range value will generally be returned. The no data value for a band is generally a special marker value used to mark pixels that are not valid data. Such pixels should generally not be displayed, nor contribute to analysis operations.

This method is the same as the C function GDALGetRasterNoDataValue().

Parameters:
pbSuccess   pointer to a boolean to use to indicate if a value is actually associated with this layer. May be NULL (default).
Returns:
the nodata value for this band.
""" ->
# function GDALGetRasterNoDataValue(arg1::GDALRasterBandH,arg2::Ptr{Cint})
#     ccall((:GDALGetRasterNoDataValue,libgdal),Cdouble,(GDALRasterBandH,Ptr{Cint}),arg1,arg2)
# end

@doc "Set the no data value for this band." ->
# function GDALSetRasterNoDataValue(arg1::GDALRasterBandH,arg2::Cdouble)
#     ccall((:GDALSetRasterNoDataValue,libgdal),CPLErr,(GDALRasterBandH,Cdouble),arg1,arg2)
# end

@doc """
Fetch the list of category names for this raster.

The return list is a "StringList" in the sense of the CPL functions. That is a NULL terminated array of strings. Raster values without associated names will have an empty string in the returned list. The first entry in the list is for raster values of zero, and so on.

The returned stringlist should not be altered or freed by the application. It may change on the next GDAL call, so please copy it if it is needed for any period of time.

This method is the same as the C function GDALGetRasterCategoryNames().

Returns:
list of names, or NULL if none.
""" ->
# function GDALGetRasterCategoryNames(arg1::GDALRasterBandH)
#     ccall((:GDALGetRasterCategoryNames,libgdal),Ptr{Ptr{Uint8}},(GDALRasterBandH,),arg1)
# end

@doc "Set the category names for this band." ->
# function GDALSetRasterCategoryNames(arg1::GDALRasterBandH,arg2::Ptr{Ptr{Uint8}})
#     ccall((:GDALSetRasterCategoryNames,libgdal),CPLErr,(GDALRasterBandH,Ptr{Ptr{Uint8}}),arg1,arg2)
# end

@doc """
Flush raster data cache.

This call will recover memory used to cache data blocks for this raster band, and ensure that new requests are referred to the underlying driver.

This method is the same as the C function GDALFlushRasterCache().

Returns:
CE_None on success.
""" ->
# function GDALFlushRasterCache(hBand::GDALRasterBandH)
#     ccall((:GDALFlushRasterCache,libgdal),CPLErr,(GDALRasterBandH,),hBand)
# end

@doc """
Fill this band with a constant value.

GDAL makes no guarantees about what values pixels in newly created files are set to, so this method can be used to clear a band to a specified "default" value. The fill value is passed in as a double but this will be converted to the underlying type before writing to the file. An optional second argument allows the imaginary component of a complex constant value to be specified.

This method is the same as the C function GDALFillRaster().

Parameters:
dfRealValue     Real component of fill value
dfImaginaryValue    Imaginary component of fill value, defaults to zero
Returns:
CE_Failure if the write fails, otherwise CE_None
""" ->
# function GDALFillRaster(hBand::GDALRasterBandH,dfRealValue::Cdouble,dfImaginaryValue::Cdouble)
#     ccall((:GDALFillRaster,libgdal),CPLErr,(GDALRasterBandH,Cdouble,Cdouble),hBand,dfRealValue,dfImaginaryValue)
# end

@doc """
Return the mask band associated with the band.

The GDALRasterBand class includes a default implementation of GetMaskBand() that returns one of four default implementations :

If a corresponding .msk file exists it will be used for the mask band.
If the dataset has a NODATA_VALUES metadata item, an instance of the new GDALNoDataValuesMaskBand class will be returned. GetMaskFlags() will return GMF_NODATA | GMF_PER_DATASET.
Since:
GDAL 1.6.0
If the band has a nodata value set, an instance of the new GDALNodataMaskRasterBand class will be returned. GetMaskFlags() will return GMF_NODATA.
If there is no nodata value, but the dataset has an alpha band that seems to apply to this band (specific rules yet to be determined) and that is of type GDT_Byte then that alpha band will be returned, and the flags GMF_PER_DATASET and GMF_ALPHA will be returned in the flags.
If neither of the above apply, an instance of the new GDALAllValidRasterBand class will be returned that has 255 values for all pixels. The null flags will return GMF_ALL_VALID.
Note that the GetMaskBand() should always return a GDALRasterBand mask, even if it is only an all 255 mask with the flags indicating GMF_ALL_VALID.

This method is the same as the C function GDALGetMaskBand().

Returns:
a valid mask band.
Since:
GDAL 1.5.0
See also:
http://trac.osgeo.org/gdal/wiki/rfc15_nodatabitmask
""" ->
# function GDALGetMaskBand(hBand::GDALRasterBandH)
#     ccall((:GDALGetMaskBand,libgdal),GDALRasterBandH,(GDALRasterBandH,),hBand)
# end

@doc """
Return the status flags of the mask band associated with the band.

The GetMaskFlags() method returns an bitwise OR-ed set of status flags with the following available definitions that may be extended in the future:

GMF_ALL_VALID(0x01): There are no invalid pixels, all mask values will be 255. When used this will normally be the only flag set.
GMF_PER_DATASET(0x02): The mask band is shared between all bands on the dataset.
GMF_ALPHA(0x04): The mask band is actually an alpha band and may have values other than 0 and 255.
GMF_NODATA(0x08): Indicates the mask is actually being generated from nodata values. (mutually exclusive of GMF_ALPHA)
The GDALRasterBand class includes a default implementation of GetMaskBand() that returns one of four default implementations :

If a corresponding .msk file exists it will be used for the mask band.
If the dataset has a NODATA_VALUES metadata item, an instance of the new GDALNoDataValuesMaskBand class will be returned. GetMaskFlags() will return GMF_NODATA | GMF_PER_DATASET.
Since:
GDAL 1.6.0
If the band has a nodata value set, an instance of the new GDALNodataMaskRasterBand class will be returned. GetMaskFlags() will return GMF_NODATA.
If there is no nodata value, but the dataset has an alpha band that seems to apply to this band (specific rules yet to be determined) and that is of type GDT_Byte then that alpha band will be returned, and the flags GMF_PER_DATASET and GMF_ALPHA will be returned in the flags.
If neither of the above apply, an instance of the new GDALAllValidRasterBand class will be returned that has 255 values for all pixels. The null flags will return GMF_ALL_VALID.
This method is the same as the C function GDALGetMaskFlags().

Since:
GDAL 1.5.0
Returns:
a valid mask band.
See also:
http://trac.osgeo.org/gdal/wiki/rfc15_nodatabitmask
""" ->
# function GDALGetMaskFlags(hBand::GDALRasterBandH)
#     ccall((:GDALGetMaskFlags,libgdal),Cint,(GDALRasterBandH,),hBand)
# end

@doc """
Adds a mask band to the current band.

The default implementation of the CreateMaskBand() method is implemented based on similar rules to the .ovr handling implemented using the GDALDefaultOverviews object. A TIFF file with the extension .msk will be created with the same basename as the original file, and it will have as many bands as the original image (or just one for GMF_PER_DATASET). The mask images will be deflate compressed tiled images with the same block size as the original image if possible.

Note that if you got a mask band with a previous call to GetMaskBand(), it might be invalidated by CreateMaskBand(). So you have to call GetMaskBand() again.

This method is the same as the C function GDALCreateMaskBand().

Since:
GDAL 1.5.0
Returns:
CE_None on success or CE_Failure on an error.
See also:
http://trac.osgeo.org/gdal/wiki/rfc15_nodatabitmask
""" ->
# function GDALCreateMaskBand(hBand::GDALRasterBandH,nFlags::Cint)
#     ccall((:GDALCreateMaskBand,libgdal),CPLErr,(GDALRasterBandH,Cint),hBand,nFlags)
# end